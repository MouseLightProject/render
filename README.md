MouseLight Rendering Pipeline
=============================

Given a set of raw 3D tiff stacks from the microscope and a tilebase.cache.yml
file containing the stitching parameters, use barycentric transforms to
generate an octree for viewing with the Janelia Workstation.

Requirements
============

Julia, version 4, plus the YAML package.

Nathan Clack's nd, tilebase, and mltk-bary libraries.

Tested with Julia v0.4.5, YAML v0.1.10, nd master (branch) / 4e2820 (commit),
ndio-series use-tre/ee05c5, ndio-tiff ndio-format-context/283a0d, tilebase
master/1d927a, and mltk-bary master/0db387.


Installation
============

Install nd, tilebase, and mltk-bary libraries using make.sh.  Be sure
to edit ```rootdir``` and ```installdir``` therein appropriately.

Install Julia by downloading a precompiled binary of the latest point
release of version 4.  Install the YAML package by starting Julia on the
unix command line and executing Pkg.add("YAML").  If desired, use the
bash environment variable JULIA_PKGDIR to place it somewhere other than
your home directory.  For example, somewhere on Julia's LOAD_PATH, like
<julia-install-dir>/share/julia/site, would permit others to use the
pipeline without having to install all of the packages themselves.

Make sure that ```RENDER_PATH```, ```LD_LIBRARY_PATH```, and ```JULIA```
in ```render```, ```monitor```, ```savelogs```, and ```merge``` are all
set appropriately.


Basic Usage
===========

First, set the desired parameters by editing a copy of parameters.jl.
At a minimum, the source variable should point to the full path of the
tilebase.cache.yml file and the destination variable to the directory in
which to save the octree.

Start the render as follows:

```
ssh login1
cd /groups/mousebrainmicro/mousebrainmicro/Software/barycentric/src/render
./render <copy_of_parameters.jl>
```

An email will be sent to you confirming that it started.  In the message
body will be a command with which you can monitor its progress:

```
./monitor <jobname> <path_to_set_parameters.jl>
```

Shown is are the RAM, CPU, disk, and i/o utilization for each node on the
cluster currently being used, updated every minute.  One can also point a
browser to http://cluster-status.int.janelia.org, or use the ```qstat```
command on the unix command line.

Once the render is done you will be sent another email with a command you
need to execute to transfer and compress the log files:

```
./savelogs <destination>
```

Don't forget to do this, as otherwise it will be difficult to subsequently
diagnose any errors.

To kill the render before it completes, use the qdel command:

```
qdel -u <yourUserId>
```

Should you kill the render, or in case it crashes or hangs before it finishes,
be sure to delete all the temporary files on the cluster nodes:

```
./janitor <destination>
```

The render can be restricted to a partial sub-volume using the
region_of_interest or morton_order variables in the copy of parameters.jl.
To merge two different such octrees from the same brain into a single octree,
use the merge script:

```
./merge <source1> <source2> ... <sourceN> <destination>
```

The merge script can also be used to fix sub-volumes that have not been
rendered correctly.  Simply re-render the region in question and merge with
the rest.

Finally, Janelia has many file systems to use for the source, destination, and
scratch spaces.  Test their relative I/O performance as follows:

```
./diskio
```


Troubleshooting
===============

If a squatter hangs, you can spoof its communication and get the director to continue
with the inter-node merge by:

```
julia> sock = connect("<node_name>.int.janelia.org",2000)
TcpSocket(open, 0 bytes waiting)

julia> println(sock,"squatter <squatter_num> is finished")
```


Similarly, if a peon segfaults:

```
const ready = r"(peon for input tile )([0-9]*)( has output tile )([1-8/]*)( ready)"
port2=2001
server2 = listen(port2)
sock2 = accept(server2)
tmp = chomp(readline(sock2))

in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
msg = "manager tells peon for input tile $in_tile_num to write output tile $out_tile_path to local_scratch"
println(sock2, msg)

while isopen(sock2) || nb_available(sock2)>0
  tmp = chomp(readline(sock2))
  tmp = chomp(readline(sock2))
  in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
  msg = "manager tells peon for input tile $in_tile_num to write output tile $out_tile_path to local_scratch"
  println(sock2, msg)
end
```


Author
======

[Ben Arthur](http://www.janelia.org/people/research-resources-staff/ben-arthur), arthurb@hhmi.org
[Scientific Computing](http://www.janelia.org/research-resources/computing-resources)
[Janelia Farm Research Campus](http://www.janelia.org)
[Howard Hughes Medical Institute](http://www.hhmi.org)

[![Picture](/hhmi_janelia_160px.png)](http://www.janelia.org)
