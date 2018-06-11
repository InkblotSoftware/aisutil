//  ==========================================================================
//  Copyright (c) 2017-2018 Inkblot Software Limited
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//  ==========================================================================

import std.stdio, std.exception, std.algorithm, std.range, std.typecons;
import aisutil.decodeprocess, aisutil.decodeprocessdef, aisutil.decprocfinstats,
       aisutil.filewriting, aisutil.geo, aisutil.filereading;

import dlangui, dlangui.core.logger;
mixin APP_ENTRY_POINT;


//  ==========================================================================
//  Load assets from disk
//  ==========================================================================

immutable string readmeText = import ("README.md");


//  ==========================================================================
//  == DML window contents layout
//  ==========================================================================

immutable string layoutText = q{
    // The whole window
    VerticalLayout { layoutWidth: fill; layoutHeight: fill;
                     backgroundColor: "#cfcfcf"

        // Start with a menu bar at the top of the window
        MainMenu { id: WindowMenu }

        // All the rest of the content in this (three rows)
        VerticalLayout { layoutWidth: fill; layoutHeight: fill; padding: 2

            // Row 1: input and output file location settings
            VerticalLayout { backgroundColor: "#000040"; padding: 2; margins: 4
    
            TextWidget { text: "Input and output file locations"
                         fontWeight: 800; fontSize: 18; textColor: white
                         alignment: center }
                VerticalLayout { backgroundColor: white; padding: 5
                    VerticalLayout { id: InputFilesPanel }
                    VerticalLayout { id: BaseOutFileSelectPanel }
                }
            }

            // Row 2: 'output settings' and 'message filtering'
            TableLayout { colCount: 2; layoutWidth: fill
    
                VerticalLayout { backgroundColor: "#000040"; padding: 2; margins: 4
                                 layoutHeight: fill
                    TextWidget { text: "Output settings"; textColor: white
                                 fontWeight: 800; fontSize: 18; alignment: center }
                    VerticalLayout { backgroundColor: white; layoutHeight: fill;
                                     padding: 5
                        VerticalLayout { id: OutputFormatPanel } 
                        VerticalLayout { id: OutputFileSplittingPanel }
                    }
                }
                VerticalLayout { backgroundColor: "#000040"; padding: 2; margins: 4
                    TextWidget { text: "Message filtering"; textColor: white
                                 fontWeight: 800; fontSize: 18; alignment: center }
                    VerticalLayout { backgroundColor: white; padding: 5
                        VerticalLayout { id: GeoBoundsPanel }
                        VerticalLayout { id: ShipTypeFilterPanel }
                        VerticalLayout { id: ShipLengthFilterPanel }
                    }
                }
            }

            // Row 3: 'run' and 'last run results' panels
            VerticalLayout { backgroundColor: "#000040"; padding: 2; margins: 4

                TextWidget { text: "Run process"
                             fontWeight: 800; fontSize: 18; textColor: white
                             alignment: center }
                TableLayout { colCount:2; layoutWidth: fill; backgroundColor: white;
                              padding: 5
                    VerticalLayout { id: RunProcessPanel }
                    VerticalLayout { id: LastRunResultsPanel }
                }
            }
        }
    }
};


//  ==========================================================================
//  == main()
//  ==========================================================================

extern (C) int UIAppMain(string[] args) {
    // dlangui logger
    version (posix) {
        // so we only see stderr logs on posix, as seems to crash on windows
        Log.setStderrLogger();
    }
    debug {
        // Only make a log file if we're in a debug build
        Log.setLogLevel(LogLevel.Debug);
    }

    // Initialise this thread's mailbox
    import std.concurrency;
    spawn ((){});

    auto app = new App (layoutText);
    
    return Platform.instance.enterMessageLoop();
}


//  ==========================================================================
//  == All GUI panels, managed together
//  ==========================================================================

//  --------------------------------------------------------------------------
//  Panel interface - all the elements of the GUI implement this

interface Panel {
    void updateGui();  // Instructs panel to prepare itself to be drawn, e.g. by
                       // setting widget state from internal panel variable state
    
    void freeze();  // Instructs panel to disable itself
    void thaw();    // The opposite
}

//  --------------------------------------------------------------------------
//  All the panels we have

class PanelGroup {
    GeoBoundsPanel           geoBoundsPanel;
    OutputFileSplittingPanel outputFileSplittingPanel;
    InputFilesPanel          inputFilesPanel;
    LastRunResultsPanel      lastRunResultsPanel;
    RunProcessPanel          runProcessPanel;
    ShipLengthFilterPanel    shipLengthFilterPanel;
    OutputFormatPanel        outputFormatPanel;
    ShipTypeFilterPanel      shipTypeFilterPanel;
    BaseOutFileSelectPanel   baseOutFileSelectPanel;

    // Call with parent window, and the fun to run when the user clicks 'go'
    this (Window window, void delegate() runProcess) {
        // TODO probably do this with static foreach and mixins
        geoBoundsPanel = new GeoBoundsPanel (window, "GeoBoundsPanel");
        outputFileSplittingPanel = new OutputFileSplittingPanel
                                       (window, "OutputFileSplittingPanel");
        inputFilesPanel = new InputFilesPanel (window, "InputFilesPanel");
        lastRunResultsPanel = new LastRunResultsPanel (window, "LastRunResultsPanel");
        runProcessPanel = new RunProcessPanel (window, "RunProcessPanel", runProcess);
        shipLengthFilterPanel = new ShipLengthFilterPanel
                                    (window, "ShipLengthFilterPanel");
        outputFormatPanel = new OutputFormatPanel (window, "OutputFormatPanel");
        shipTypeFilterPanel = new ShipTypeFilterPanel (window, "ShipTypeFilterPanel");
        baseOutFileSelectPanel = new BaseOutFileSelectPanel
                                     (window, "BaseOutFileSelectPanel");

        all() .each!(e => assert(e));
    }

    void freeze () { all().each!(e => e.freeze()); }
    void thaw ()   { all().each!(e => e.thaw()); }
    void updateGui () { all().each!(e => e.updateGui()); }

    // Returns a slice with all panels in this panelgroup
    private Panel[] all () {
        Panel[] res;
        static foreach (mem; __traits(allMembers, typeof(this))) {
            // TODO clean this up a bit
            import std.traits;
            {
                static if (mem != "Monitor") {
                    alias Mem = typeof(__traits(getMember, this, mem));
                    alias Ints = InterfacesTuple!Mem;
                    // TODO use canFind or simlar
                    static if (is(Ints[0] == Panel)) {
                        res ~= __traits(getMember, this, mem);
                    }
                }
            }
        }
        return res;
    }
}
            

//  ==========================================================================
//  == Core application class
//  ==========================================================================

class App {
    Window _window;
    Widget _mainWidget;
    MainMenu _menu;

    // Controls are frozen while a decode process is running
    bool _decodeProcessRunning = false;

    PanelGroup _panels;

    TimedTaskRunner _threadMsgFetcher;

    DecodeProcessDef _decProcDef;  // what decode process does the user want?
    Nullable!DecProcFinStats _decProcRunStats;  // last results of any run
    Nullable!DecodeProcessCurRunningStats _decProcCurRunStats;  // last such message received
    
    this (in string mainLayoutString) {
        _window = Platform.instance.createWindow
            ("AIS vessel data decoder", null,
             WindowFlag.MeasureSize | WindowFlag.Resizable);
        
        _mainWidget = parseML (mainLayoutString);
        _window.mainWidget = _mainWidget;

        _panels = new PanelGroup (_window, &runProcess);

        // Add the menu
        _menu = _mainWidget .childById!MainMenu ("WindowMenu");
        assert (_menu);
        auto helpMenu = new MenuItem(new Action(1, "Help"d));
        helpMenu.add (new Action (1002, "Documentation"d));
        helpMenu.add (new Action (1001, "Copyright and licenses"d));
        helpMenu.menuItemClick = delegate (MenuItem item) {
            if (item.id == 1001)
                showDialog_copyrightAndLicenses();
            else if (item.id == 1002)
                showDialog_documentation();
            else
                assert (0);
            return true;
        };
        _menu.menuItems = new MenuItem() .add(helpMenu);   // just one menu stem

        _threadMsgFetcher = new TimedTaskRunner (_mainWidget, 100,
                                                 (){auto msg = getLastThreadMsg();
                                                    if (! msg.peek!NoThreadMsg)
                                                        onThreadMessage (msg); });
        _threadMsgFetcher.start ();

        _window.show ();
        updateGui();
    }

    // -- Showing dialogs

    private void showDialog_copyrightAndLicenses () {
        import aisutil.licenses;
        auto dlg = new ScrollingMessageBox
                         (_window,
                          UIString.fromRaw ("Copyright and licenses"),
                          UIString.fromRaw (allLicenses));
        dlg.show();
    }
    private void showDialog_documentation () {
        auto text = "Latest documentation can be found at:\n" ~
                    "http://github.com/InkblotSoftware/aisutil\n" ~
                    "\n\n" ~
                    readmeText;
        auto dlg = new ScrollingMessageBox
                         (_window,
                          UIString.fromRaw("Documentation"),
                          UIString.fromRaw(text));
        dlg.show ();
    }

    // -- Event handlers

    private void runProcess () {
        // For showing "you entered bad values" messages to the user
        auto showMsg = (string msg) {
            _window.showMessageBox (UIString.fromRaw ("Input settings error"),
                                    UIString.fromRaw (msg));
        };

        // Geo bounds
        try {
            _decProcDef.geoBounds = _panels.geoBoundsPanel .choice();
        } catch (Exception e) {
            Log.d (e.msg);
            showMsg ("Non-numeric geo bounds values entered");
            return;
        }

        // These don't throw
        _decProcDef.messageOutputFormat = _panels.outputFormatPanel.choice ();
        _decProcDef.msgOutSegment   = _panels.outputFileSplittingPanel .choice ();
        _decProcDef.filtSimShipType = _panels.shipTypeFilterPanel.choice ();
        _decProcDef.filtShipLenCat  = _panels.shipLengthFilterPanel.choice ();

        // Input files
        try {
            _decProcDef.inputFiles = _panels.inputFilesPanel.filesChoice().idup;
        } catch (Exception e) {
            Log.d (e.msg);
            showMsg ("No input files selected");
            return;
        }
        // Doesn't throw
        _decProcDef.aisFileFormat = _panels.inputFilesPanel.formatChoice();
            
        // Ouptut files
        try {
            _decProcDef.outputRootFile = _panels.baseOutFileSelectPanel.choice ();
        } catch (Exception e) {
            Log.d (e.msg);
            showMsg ("Invalid (or missing) output file location");
            return;
        }

        _decProcCurRunStats.nullify();
        _decProcRunStats.nullify();

        Log.d ("-- SPAWNING WORKER WITH PROC DEF: ", _decProcDef);
        spawnDecProcWorker (_decProcDef);

        _decodeProcessRunning = true;
        updateGui();
        return;
    }

    // -- Thread message handler

    private void onThreadMessage (ThreadMsg msg) {
        if (auto cs = msg.peek!DecodeProcessCurRunningStats) {
            Log.d("-- THREAD GOT CUR RUNNING STATS: ", cs);
            _decProcCurRunStats = *cs;
            _panels.runProcessPanel.setFrom (*cs);
        } else
        if (auto rs = msg.peek!DecProcFinStats) {
            Log.d ("-- THREAD GOT RUN FIN STATS");
            _decProcRunStats = *rs;
            _decodeProcessRunning = false;
            _panels.runProcessPanel.setFrom (*rs);
        }
        else {
            assert (0);
        }

        updateGui();
    }

    // -- Update the gui with current app state

    private void updateGui () {
        if (! _decProcRunStats.isNull)
            _panels.lastRunResultsPanel.setFrom (_decProcRunStats);
        
        if (_decodeProcessRunning) {
            _panels.freeze ();
        } else {
            _panels.thaw ();
        }
    }

    // -- Helpers

    // Set the progress bar in accordance with a value between 0 and 1
    private void spawnDecProcWorker (DecodeProcessDef pd) {
        import std.concurrency;
        
        auto workerFun = function() {
            try {
                auto rec = receiveOnly! (Tid, DecodeProcessDef) ();
                auto guiTid = rec[0];
                auto def = rec[1];
                
                auto sendProgress = (DecodeProcessCurRunningStats crStats) {
                    guiTid.send (crStats);
                };
                auto stats = executeDecodeProcess (def, sendProgress);
                guiTid.send (stats);
                
            } catch (Exception e) {
                Log.d ("-- WORKER THREW EXCEPTION: ", e);
                assert (0);
            }
        };
        auto worker = spawn (workerFun);
        worker.send (thisTid, pd);
    }
}


//  ==========================================================================
//  == Custom dialog boxes
//  ==========================================================================

//  --------------------------------------------------------------------------
//  As MessageBox dialog, but scrolls long text rather than overflowing

import dlangui.dialogs.msgbox;

class ScrollingMessageBox : MessageBox {
    import dlangui.dialogs.dialog;
    UIString _message;
    
    this (Window window, UIString caption, UIString message) {
        super (caption, message, window);
        _message = message;
    }
    override void initialize () {
        layoutHeight(600);
        
        auto textWidget = new MultilineTextWidget ("msg", _message);
        textWidget .layoutWidth(FILL_PARENT) .layoutHeight(FILL_PARENT)
                   .fontFace("Courier New") .fontSize(14);

        auto scrollWidget = new ScrollWidget ("SCROLL");
        scrollWidget .minHeight(600) .minWidth(700);
        
        scrollWidget.contentWidget = textWidget;
        addChild (scrollWidget);

        import dlangui.dialogs.dialog;
        addChild (createButtonsPanel ([ACTION_OK], 0, 0));
    }
}


//  ==========================================================================
//  == Concurrency
//  ==========================================================================

//  --------------------------------------------------------------------------
//  TimedTaskRunner - runs a delegate at pre-set intervals
//    This is implemented as a Widget so it fits into the dlangui signals system.
//    Pass the window.mainWidget as first argument; this adds itself as a child.

class TimedTaskRunner : Widget {
    private int _delaySecs;
    private void delegate() _fun;

    this (Widget mainWidget, int delaySecs, void delegate() fun) {
        _delaySecs = delaySecs; _fun = fun;
        mainWidget.addChild (this);
    }
    override bool onTimer(ulong id) {
        _fun();
        return true;
    }
    void start() {
        setTimer(_delaySecs);
    }
}


//  --------------------------------------------------------------------------
//  Thread message fetching

struct NoThreadMsg {}

import std.variant;
alias ThreadMsg = Algebraic!(NoThreadMsg,
                             DecodeProcessCurRunningStats,
                             DecProcFinStats);

// Get a message from the current thread's mailbox, formatted as a ThreadMsg.
// Dies if a different kind of message arrives there
ThreadMsg getOneThreadMsg () {
    import std.concurrency, core.time;

    ThreadMsg res = ThreadMsg (NoThreadMsg());

    // Only change res if there's a message to fill it with
    bool gotMsg = receiveTimeout(
        Duration.zero,  // stop immediately if no message in box
        (DecodeProcessCurRunningStats crs) {res = crs;},
        (DecProcFinStats                s) {res = s;},
        (Variant any) {
            writeln("========= RECEIVED OTHER MESSAGE: ", &any, " - ", any.type.toString);
            assert(0);
        }
    );

    return res;
}

// Goes through all pending messages and returns the last, or NoThreadMsg if
// none was available
ThreadMsg getLastThreadMsg () {
    auto msg = getOneThreadMsg ();

    auto testMsg = getOneThreadMsg ();
    while (! testMsg.peek! NoThreadMsg) {
        msg = testMsg;
        testMsg = getOneThreadMsg();
    }

    return msg;
}


//  ==========================================================================
//  == Individual panel implementations
//  ==========================================================================

//  --------------------------------------------------------------------------
//  Panel: select geo bounds to filter inside

class GeoBoundsPanel : Panel {
    EditLine _minLat, _maxLat, _minLon, _maxLon;

    // selfId is ID of VerticalLayout in layout.txt file
    this (Window window, string selfId) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        
        _minLat = new EditLine ("",  "-90");
        _maxLat = new EditLine ("",   "90");
        _minLon = new EditLine ("", "-180");
        _maxLon = new EditLine ("",  "180");
        
        // Row 1
        self.addChild ((new TextWidget ("", UIString.fromRaw("Include geo bounds:")))
                           .fontWeight(800) .fontSize(14));

        // Row 2
        auto table = new TableLayout ();
        self.addChild (table);
        table.colCount = 4;

        // Row 2 table cells
        TextWidget twid (string str) {return new TextWidget("", UIString.fromRaw(str));}
        [twid("Min Lat"), _minLat, _maxLat, twid("Max Lat"),
         twid("Min Lon"), _minLon, _maxLon, twid("Max Lon")]
            .each!(e => table.addChild(e));
    }

    GeoBounds choice () {
        return GeoBounds (to!double(_minLat.text), to!double(_maxLat.text),
                          to!double(_minLon.text), to!double(_maxLon.text));
    }

    override void updateGui () {}
    override void freeze () {allBoxes.each !(w => w.enabled = false);}
    override void thaw ()   {allBoxes.each !(w => w.enabled = true);}

    private {
        Widget[] allBoxes () {return [_minLat, _maxLat, _minLon, _maxLon];}
    }
}


//  --------------------------------------------------------------------------
//  Panel: output file segmentation

class OutputFileSplittingPanel : Panel {
    RadioButton _allInOne, _vesType, _vesLen, _byDay;

    // selfId is ID if VerticalLayout in layout.txt file
    this (Window window, string selfId) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        self.addChild ((new TextWidget("", UIString.fromRaw("Output file splitting:")))
                       .fontWeight(800) .fontSize(14));
            
        RadioButton rb (string label) {return new RadioButton("", UIString.fromRaw(label));}
        _allInOne = rb ("None (all data in one file)");
        _allInOne.checked = true;
        _vesType  = rb ("By vessel type");
        _vesLen   = rb ("By vessel length");
        _byDay    = rb ("By AIS message day");
        [_allInOne, _vesType, _vesLen, _byDay].each!(e => self.addChild(e));
    }
    MessageOutputSegmentation choice () {
        if (_allInOne .checked) return MessageOutputSegmentation.AllInOne;
        if (_vesType  .checked) return MessageOutputSegmentation.VesselCategories;
        if (_vesLen   .checked) return MessageOutputSegmentation.ShipLenCat;
        if (_byDay    .checked) return MessageOutputSegmentation.TimestampDay;
        assert (0);
    }

    override void updateGui () {}
    override void freeze () {allItems.each!(e => e.enabled = false);}
    override void thaw ()   {allItems.each!(e => e.enabled = true);}

    private Widget[] allItems() {return [_allInOne, _vesType, _vesLen, _byDay];}
}


//  --------------------------------------------------------------------------
//  Panel: Input files selection

class InputFilesPanel : Panel {
    Window _window;
    string[] _files = [];
    Button _addBut, _clearBut;
    StringListWidget _filesListWidget;
    StringListAdapter _filesList;
    RadioButton _nmeaFormat, _mcaFormat;
    
    this (Window window, string selfId) {
        _window = window;
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        self.addChild ((new TextWidget ("", UIString.fromRaw
                                              ("Select input AIS files:")))
                           .fontWeight(800) .fontSize(14));

        // -- Row 1: file choice buttons and selected files display box
        auto hlay = new HorizontalLayout ();
        hlay.layoutWidth = FILL_PARENT;
        self.addChild (hlay);

        // -- Row 1, Col 1: file choice buttons (added below)
        auto vhlay = new VerticalLayout ();
        hlay.addChild (vhlay);
        
        _addBut = new Button ("", UIString.fromRaw("Add file..."));
        _addBut.click = &onClick_addFile;
        vhlay.addChild (_addBut);
        
        _clearBut = new Button ("", UIString.fromRaw("Clear"));
        _clearBut.click = &onClick_clearFiles;
        vhlay.addChild (_clearBut);

        // -- Row 1, Col 2: selected files display widget
        _filesList = new StringListAdapter ();
        _filesListWidget = new StringListWidget ();
        _filesListWidget .alignment(Align.Left | Align.Top)
                         .layoutWidth(FILL_PARENT) .layoutHeight(FILL_PARENT)
                         .maxHeight(130)
                         .backgroundColor("#efefef");
        _filesListWidget.ownAdapter = _filesList;
        hlay.addChild (_filesListWidget);
        
        // -- Row 2: input format radio buttons
        auto formatRow = new HorizontalLayout ();
        formatRow.addChild (new TextWidget ("", "File format:"d));
        formatRow.addChild (_nmeaFormat = new RadioButton ("", "NMEA (normal)"d));
        formatRow.addChild (_mcaFormat = new RadioButton ("", "UK MCA/MMO"d));
        _nmeaFormat.checked = true;
        self.addChild (formatRow);
    }

    string[] filesChoice () {
        enforce (_files.length);
        return _files.dup(); }
    AisFileFormat formatChoice () {
        if (_nmeaFormat.checked) return AisFileFormat.NMEA;
        if (_mcaFormat .checked) return AisFileFormat.MCA;
        assert (0);
    }

    override void freeze () {allElems().each!(e => e.enabled = false);}
    override void thaw ()   {allElems().each!(e => e.enabled = true);}
    import std.string;
    override void updateGui () {
        // We rebuild _filesList rather than calling clear() as the latter
        // leads to range violations when the user later clicks on the rows.
        // Unclear whether this is a dlangui bug or incorrect use.
        _filesList = new StringListAdapter ();
        _filesListWidget.ownAdapter = _filesList;
        foreach (path; _files) {
            _filesList.add (UIString.fromRaw(path));
        }
    }

    private {
        bool onClick_addFile (Widget src) {
            import dlangui.dialogs.filedlg, dlangui.dialogs.dialog;
            auto dlg = new FileDialog (UIString.fromRaw("Selece one or more NMEA files"),
                                       _window);
            dlg.allowMultipleFiles = true;
            dlg.dialogResult = delegate (Dialog dd, const Action result) {
                if (result.id == ACTION_OPEN) {
                    auto filenames = (cast(FileDialog)dd).filenames;
                    foreach (fn; filenames) {
                        if (! _files.canFind(fn))
                            _files ~= fn;
                    }
                    updateGui();
                }
            };
            dlg.show();
            return true;
        }
        bool onClick_clearFiles (Widget src) {
            _files = [];
            updateGui();
            return true;
        }
        Widget[] allElems () {return [_filesListWidget, _addBut, _clearBut,
                                      _nmeaFormat, _mcaFormat];}
    }
}


//  --------------------------------------------------------------------------
//  Panel: Last run statistics display

class LastRunResultsPanel : Panel {
    private Window _window;
    private Nullable!DecProcFinStats _stats;
    private TextWidget _inputLines, _inputBytes, _msgsRead, _msgsPassed, _runTime;

    // Making labels to go into the table
    private static TextWidget leftLab (string label) {
        auto wid = new TextWidget (null, UIString.fromRaw(label));
        wid.alignment (Align.Right | Align.VCenter);
        return wid; }
    private static TextWidget rightLab () {
        auto wid = new TextWidget (null, UIString.fromRaw("-"));
        wid.alignment (Align.Left | Align.VCenter);
        return wid; }

    this (Window window, string selfId) {
        _window = window;
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);

        // Panel title
        self.addChild ((new TextWidget(null, "Last run results:"d))
                           .fontWeight(800) .fontSize(14)
                           .alignment(Align.Center));

        auto table = new TableLayout ().colCount(2);
        self.addChild (table);

        table.addChild (leftLab("Input lines:"));
        table.addChild (_inputLines = rightLab ());
        table.addChild (leftLab("Input bytes:"));
        table.addChild (_inputBytes = rightLab ());
        table.addChild (leftLab("AIS messages read:"));
        table.addChild (_msgsRead = rightLab ());
        table.addChild (leftLab("AIS messages passed filters:"));
        table.addChild (_msgsPassed = rightLab ());
        table.addChild (leftLab("Run time (seconds):"));
        table.addChild (_runTime = rightLab ());
    }

    // Inform the panel new results have arrived
    void setFrom (DecProcFinStats stats) { _stats = stats; updateGui(); }

    override void freeze () {}
    override void thaw () {}
    override void updateGui () {
        if (_stats.isNull)
            return;
        _inputLines.text = UIString.fromRaw( to!string (_stats.inputLines));
        _inputBytes.text = UIString.fromRaw( to!string (_stats.inputBytes));
        _msgsRead.text   = UIString.fromRaw( to!string (_stats.parsedMsgs));
        _msgsPassed.text = UIString.fromRaw( to!string (_stats.parsedMsgsWritten));
        _runTime.text    = UIString.fromRaw( to!string (_stats.runTimeSecs));
    }
}


//  --------------------------------------------------------------------------
//  Panel: Run decode process and monitor progress

class RunProcessPanel : Panel {
    // runFun() is called whenever the user hits the 'run' button
    this (Window window, string selfId, void delegate() runFun) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        _runFun = runFun;
        
        // Panel title
        self.addChild ((new TextWidget (null, "Run using above settings:"d))
                           .fontWeight(800) .fontSize(14));

        // Row with button and progress bar
        auto hor = new HorizontalLayout ();
        self.addChild (hor);
        hor.layoutWidth = FILL_PARENT;
        hor.addChild (_runBut = new Button (null, "Run..."d));
        _runBut .fontWeight(800);
        hor.addChild (_bar = new ProgressBarWidget());
        _bar.maxWidth = 200;
        _bar.minWidth = 200;
        
        _runBut.click = &onClick_runBut;
        _bar.animationInterval = 50;

        // Row with text status
        // TODO remove duplication of this label literal, also in updateGui
        self.addChild (_textStatus = new TextWidget (null, "No process run yet"d));
    }

    void setFrom (DecProcFinStats stats) {
        _neverRun = false;
        _totalBytes = stats.inputBytes;
        _curBytes = stats.inputBytes;
        updateGui();
    }
    void setFrom (DecodeProcessCurRunningStats stats) {
        _neverRun = false;
        _totalBytes = stats.totalBytesInInput;
        _curBytes = stats.bytesProcessed;
        updateGui();
    }

    override void updateGui () {
        double prop = (cast(double)_curBytes) / (cast(double)_totalBytes);
        _bar.progress = cast(int) (1000 * prop);
        if (_neverRun) {
            _textStatus.text = "No process run yet"d;
        } else {
            if (_curBytes == _totalBytes) {
                // Finished
                _textStatus.text = "Completed"d;
            } else {
                // Still running
                _textStatus.text = UIString.fromRaw
                    (to!string(_curBytes) ~ " of " ~
                     to!string(_totalBytes) ~ " bytes processed");
            }
        }
    }
    override void freeze () { _runBut.enabled = false; }
    override void thaw ()   { _runBut.enabled = true; }

    private {
        Button _runBut;
        ProgressBarWidget _bar;
        TextWidget _textStatus;
        long _totalBytes, _curBytes;
        bool _neverRun = true;
        void delegate() _runFun;

        bool onClick_runBut (Widget src) {
            _runFun();
            return true;
        }
    }
}


//  --------------------------------------------------------------------------
//  Panel: ship length category filtering

class ShipLengthFilterPanel : Panel {
    this (Window window, string selfId) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        self.addChild ((new TextWidget(null, "Include vessels of (broadcast) length:"d))
                           .fontWeight (800) .fontSize (14));
        self.addChild (_dontFilter = newRB("All vessels"));
        self.addChild (_m0to5      = newRB("Under 5 metres (exc)"));
        self.addChild (_m5to20     = newRB("Between 5 and 20 metres (inc, exc)"));
        self.addChild (_mAbove20   = newRB("Above 20 metres (inc)"));
        _dontFilter.checked = true;
    }
    
    MmsiFilterShipLenCat choice () {
        if (_dontFilter.checked) return MmsiFilterShipLenCat.DontFilter;
        if (_m0to5     .checked) return MmsiFilterShipLenCat.OnlyMetres0to5;
        if (_m5to20    .checked) return MmsiFilterShipLenCat.OnlyMetres5to20;
        if (_mAbove20  .checked) return MmsiFilterShipLenCat.OnlyMetresAbove20;
        assert (0);
    }

    override void freeze () { [_dontFilter, _m0to5, _m5to20, _mAbove20]
                                  .each !(e => e.enabled = false); }
    override void thaw () {   [_dontFilter, _m0to5, _m5to20, _mAbove20]
                                  .each !(e => e.enabled = true); }
    override void updateGui () {} // nop

    private {
        RadioButton _dontFilter, _m0to5, _m5to20, _mAbove20;
        // Ctr helper
        static RadioButton newRB (string label) {
            return new RadioButton(null, UIString.fromRaw(label)); }
    }
}

    
//  --------------------------------------------------------------------------
//  Panel: message output format selection

class OutputFormatPanel : Panel {
    this (Window window, string selfId) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        
        self.addChild ((new TextWidget(null, "Output format:"d))
                           .fontWeight(800) .fontSize(14));
        self.addChild (_csv = new RadioButton(null, "CSV"d));
        self.addChild (_ndjson = new RadioButton
                                       (null, "ND-JSON (newline-delimited JSON)"d));
        _csv.checked = true;
    }
    MessageOutputFormat choice () {
        if (_ndjson.checked) return MessageOutputFormat.NDJSON;
        if (_csv   .checked) return MessageOutputFormat.CSV;
        assert (0);
    }
    override void freeze () {_ndjson.enabled = false; _csv.enabled = false;}
    override void thaw ()   {_ndjson.enabled = true;  _csv.enabled = true;}
    override void updateGui () {} // nop
    
    private {
        RadioButton _ndjson, _csv;
    }
}


//  --------------------------------------------------------------------------
//  Panel: ship type filter selection ('simple ship type' format)

class ShipTypeFilterPanel : Panel {
    this (Window window, string selfId) {
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        self.addChild ((new TextWidget(null, "Include vessels of (broadcast) type:"d))
                           .fontWeight(800) .fontSize(14));
        
        self.addChild (_dontFilter = newRB("All vessels"));
        self.addChild (_fishing    = newRB("Fishing"));
        self.addChild (_cargo      = newRB("Cargo"));
        self.addChild (_tanker     = newRB("Tanker"));
        _dontFilter.checked = true;
    }
    MmsiFilterSimpleShiptype choice () {
        if (_dontFilter.checked) return MmsiFilterSimpleShiptype.DontFilter;
        if (_fishing   .checked) return MmsiFilterSimpleShiptype.OnlyFishing;
        if (_cargo     .checked) return MmsiFilterSimpleShiptype.OnlyCargo;
        if (_tanker    .checked) return MmsiFilterSimpleShiptype.OnlyTanker;
        assert (0);
    }
    override void freeze () { [_dontFilter, _fishing, _cargo, _tanker]
                                  .each!(e => e.enabled = false); }
    override void thaw () {   [_dontFilter, _fishing, _cargo, _tanker]
                                  .each!(e => e.enabled = true); }
    override void updateGui () {} // nop

    private {
        RadioButton _dontFilter, _fishing, _cargo, _tanker;
        static RadioButton newRB (string label) {
            return new RadioButton (null, UIString.fromRaw(label)); }
    }
}


//  --------------------------------------------------------------------------
//  Panel: base file location selection

class BaseOutFileSelectPanel : Panel {
    this (Window window, string selfId) {
        _window = window;
        auto self = window.mainWidget .childById!VerticalLayout (selfId);
        assert (self);
        
        self.addChild ((new TextWidget(null, "Main output file:"d))
                           .fontWeight(800) .fontSize(14));

        // We have the 'select' button to the left of the path-displaying text
        auto hlay = new HorizontalLayout ();
        self.addChild (hlay);
        hlay.addChild (_select = new Button(null, "Select..."d));
        hlay.addChild (_pathDisplay = new MultilineTextWidget(null, ""d));
        
        _select.click = &onClick_select;
        
        updateGui();
    }

    string choice () {
        // sanity checks
        enforce (_path != "");
        enforce (_path != "..");
        enforce (_path != "/");
        enforce (_path != "\\");
        return _path; }

    override void updateGui () { _pathDisplay.text = UIString.fromRaw(_path); }
    override void freeze () { _select.enabled = false; }
    override void thaw ()   { _select.enabled = true; }
    
    private {
        Button _select;
        MultilineTextWidget _pathDisplay;
        string _path = "AIS_DATA.txt";  // set to this by default
        Window _window;

        bool onClick_select (Widget src) {
            import dlangui.dialogs.filedlg, dlangui.dialogs.dialog;
            auto dlg = new FileDialog (UIString.fromRaw("Select base output file"),
                                       _window, null, FileDialogFlag.Save);
            dlg.dialogResult = delegate (Dialog dd, const Action result) {
                if (result.id == ACTION_SAVE) {
                    _path = (cast(FileDialog)dd).filename;
                    if (! _path.endsWith(".txt"))
                        _path ~= ".txt";
                    updateGui();
                }
            };
            dlg.show();
            return true;
        }
    }
}
            
