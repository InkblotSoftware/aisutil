C interface wrapper round a subset of libais.

Amongst other things this lets us freeze the exposed ABI even
as libais' ABI changes, which it does quite a bit.

We also impose extra string ' ' and '@' right-end trimming
that libais doesn't do.

And we impose the gpsd naming scheme for members rather rather
than libais', as the former is at least clearly specified.