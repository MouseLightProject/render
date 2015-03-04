Basic Usage
===========

Three executables are provided.  See the documentation within each of
these bash scripts for command line syntax.

**render**  render a set of tiles using a barycentric transform to an octree

**janitor**  delete temporary files on the cluster if a render is aborted

**merge**  combine two partial octrees

**diskio**  measure i/o transfer rates to /scratch, /nobackup, /groups, & /tier2


Installation
============

Install nd, tilebase, and mltk-bary libraries using make.sh.  Be sure to edit
```rootdir``` and ```installdir``` therein appropriately.

Install Julia by either downloading a precompiled binary, or building from source.
For the latter, create Make.user with

```
OPENBLAS_DYNAMIC_ARCH=0
prefix=/path/to/install/directory/
```

and create base/user.img with

```
require("YAML")
```

Make sure that ```RENDER_PATH```, ```LD_LIBRARY_PATH```, and ```JULIA``` in
```render```, ```monitor```, and ```merge``` are all set appropriately.


Troubleshooting
===============

If a squatter hangs, you can spoof its communication and get the director to continue
with the inter-node merge by:

julia> sock = connect("<node_name>.int.janelia.org",2000)
TcpSocket(open, 0 bytes waiting)

julia> println(sock,"squatter <squatter_num> is finished")


Author
======

[Ben Arthur](http://www.janelia.org/people/research-resources-staff/ben-arthur), arthurb@hhmi.org
[Scientific Computing](http://www.janelia.org/research-resources/computing-resources)
[Janelia Farm Research Campus](http://www.janelia.org)
[Howard Hughes Medical Institute](http://www.hhmi.org)

[![Picture](/hhmi_janelia_160px.png)](http://www.janelia.org)
