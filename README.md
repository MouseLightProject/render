MouseLight Rendering Pipeline
=============================

Given a set of raw 3D tiff stacks from the microscope and a tilebase.cache.yml
file containing the stitching parameters, use barycentric transforms to
generate an octree for viewing with the Janelia Workstation.


Requirements
============

Julia, version 0.7, plus the YAML, JLD2, Images, HDF5, Morton, Gadfly, Colors, and
Cairo packages.

Nathan Clack's mltk-bary library.

Tested with Julia v0.6.0, YAML v0.3.2, JLD2 v0.1.2, Images v0.17.0, HDF5 v0.10.3, Morton
v0.0.1, Gadfly v1.0.1, Colors v0.9.5, Cairo v0.5.6 and mltk-bary master/84e15364.


Installation
============

Install the mltk-bary library using make.sh.  Be sure to edit ```rootdir```
and ```installdir``` therein appropriately.

Download a precompiled binary of of version 0.7.  Install the required
packages by changing to the directory of the repository, starting Julia on
the unix command line, entering Pkg mode by pressing `]`, and then invoking
the `instantiate` and `precompile` commands.

Make sure that ```RENDER_PATH```, ```LD_LIBRARY_PATH```, ```JULIA```,
and ```JULIA_PROJECT``` in ```render```, ```monitor```, and ```project```
are all set appropriately.


Basic Usage
===========

First, set the desired parameters by editing a copy of src/parameters.jl.
At a minimum, the source variable should point to the full path of the
tilebase.cache.yml file and the destination variable to the directory in
which to save the octree.

Start the render as follows:

```
ssh login1
cd /groups/mousebrainmicro/mousebrainmicro/Software/barycentric/src/render
./render <copy-of-parameters.jl>
```

To watch its progress check the tail of the monitor.log file.

Should you kill the render, or in case it crashes or hangs before it finishes,
be sure to delete all the temporary files on the cluster nodes:

```
./janitor <destination>
```

There is also a utility to create 2D projections from a 3D octree.  As with
the renderer, the settings are stored in a file, src/projection-parameters.jl.

```
src/project <copy-of-projection-parameters.jl>
```


Author
======

[Ben Arthur](http://www.janelia.org/people/research-resources-staff/ben-arthur), arthurb@hhmi.org
[Scientific Computing](http://www.janelia.org/research-resources/computing-resources)
[Janelia Farm Research Campus](http://www.janelia.org)
[Howard Hughes Medical Institute](http://www.hhmi.org)

[![Picture](/hhmi_janelia_160px.png)](http://www.janelia.org)
