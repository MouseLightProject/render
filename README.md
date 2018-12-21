MouseLight Rendering Pipeline
=============================

Given a set of raw 3D tiff stacks from the microscope and a tilebase.cache.yml
file containing the stitching parameters, use barycentric transforms to
generate an octree for viewing with the Janelia Workstation.

Requirements
============

Julia, version 0.7, plus the YAML, Images, HDF5, Morton, Gadfly, Colors, and
Cairo packages.

Nathan Clack's mltk-bary library.

Tested with Julia v0.6.0, YAML v0.3.2, Images v0.17.0, HDF5 v0.10.3, Morton
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
and ```JULIA_PKGDIR``` in ```render```, ```monitor```, and ```savelogs```
are all set appropriately.


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

Shown are the RAM, CPU, disk, and i/o utilization for each node on the
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

You might also want to quantify the time spent in each section of the rendering
algorithm:

```
julia ./beancounter.jl <destination>
```

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
tmp = readline(sock2)

in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
msg = string("manager tells peon for input tile ",in_tile_num,
      " to write output tile ",out_tile_path," to local_scratch")
println(sock2, msg)

while isopen(sock2) || nb_available(sock2)>0
  tmp = readline(sock2)
  tmp = readline(sock2)
  in_tile_num, out_tile_path = match(ready,tmp).captures[[2,4]]
  if read(STDIN,1)==[0x0a]  # <return>
    msg = string("manager tells peon for input tile ",in_tile_num,
          " to write output tile ",out_tile_path," to local_scratch")
  else
    msg = string("manager tells peon for input tile ",in_tile_num,
          " to merge output tile ",out_tile_path," to shared_scratch")
  end
  println(sock2, msg)
end
```


To see how many RAM slots were used:

```
grep "using RAM slot" <full-path-to-squatter.log> | cut -d' ' -f 5 | sort | uniq | less
```


Author
======

[Ben Arthur](http://www.janelia.org/people/research-resources-staff/ben-arthur), arthurb@hhmi.org
[Scientific Computing](http://www.janelia.org/research-resources/computing-resources)
[Janelia Farm Research Campus](http://www.janelia.org)
[Howard Hughes Medical Institute](http://www.hhmi.org)

[![Picture](/hhmi_janelia_160px.png)](http://www.janelia.org)
