### https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/

#=
uint32 EncodeMorton2(uint32 x, uint32 y)
{
  return (Part1By1(y) << 1) + Part1By1(x);
}

uint32 EncodeMorton3(uint32 x, uint32 y, uint32 z)
{
  return (Part1By2(z) << 2) + (Part1By2(y) << 1) + Part1By2(x);
}

// "Insert" a 0 bit after each of the 16 low bits of x
uint32 Part1By1(uint32 x)
{
  x &= 0x0000ffff;                  // x = ---- ---- ---- ---- fedc ba98 7654 3210
  x = (x ^ (x <<  8)) & 0x00ff00ff; // x = ---- ---- fedc ba98 ---- ---- 7654 3210
  x = (x ^ (x <<  4)) & 0x0f0f0f0f; // x = ---- fedc ---- ba98 ---- 7654 ---- 3210
  x = (x ^ (x <<  2)) & 0x33333333; // x = --fe --dc --ba --98 --76 --54 --32 --10
  x = (x ^ (x <<  1)) & 0x55555555; // x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
  return x;
}

// "Insert" two 0 bits after each of the 10 low bits of x
uint32 Part1By2(uint32 x)
{
  x &= 0x000003ff;                  // x = ---- ---- ---- ---- ---- --98 7654 3210
  x = (x ^ (x << 16)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
  x = (x ^ (x <<  8)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
  x = (x ^ (x <<  4)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
  x = (x ^ (x <<  2)) & 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
  return x;
}
=#

function Compact1By1(x::Int)
  x &= 0x55555555;                   # x = -f-e -d-c -b-a -9-8 -7-6 -5-4 -3-2 -1-0
  x = (x | (x >>  1)) & 0x33333333;  # x = --fe --dc --ba --98 --76 --54 --32 --10
  x = (x | (x >>  2)) & 0x0f0f0f0f;  # x = ---- fedc ---- ba98 ---- 7654 ---- 3210
  x = (x | (x >>  4)) & 0x00ff00ff;  # x = ---- ---- fedc ba98 ---- ---- 7654 3210
  x = (x | (x >>  8)) & 0x0000ffff;  # x = ---- ---- ---- ---- fedc ba98 7654 3210
  x+1
end

function Compact1By2(x::Int)
  x &= 0x09249249;                   # x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
  x = (x | (x >>  2)) & 0x030c30c3;  # x = ---- --98 ---- 76-- --54 ---- 32-- --10
  x = (x | (x >>  4)) & 0x0300f00f;  # x = ---- --98 ---- ---- 7654 ---- ---- 3210
  x = (x | (x >>  8)) & 0xff0000ff;  # x = ---- --98 ---- ---- ---- ---- 7654 3210
  x = (x | (x >> 16)) & 0x000003ff;  # x = ---- ---- ---- ---- ---- --98 7654 3210
  x+1
end

function morton2cartesian(m::Int)
  m -= 1
  Compact1By1(m>>0), Compact1By1(m>>1)
end

function morton3cartesian(m::Int)
  m -= 1
  Compact1By2(m>>0), Compact1By2(m>>1), Compact1By2(m>>2)
end


function tree2cartesian(t::Vector{Int}, xmin, xmax, ymin, ymax)
  if t[1]==1 || t[1]==2
    next_ymin, next_ymax = ymin, ymin+(ymax-ymin)/2
  else
    next_ymin, next_ymax = ymin+(ymax-ymin)/2, ymax
  end
  if t[1]==1 || t[1]==3
    next_xmin, next_xmax = xmin, xmin+(xmax-xmin)/2
  else
    next_xmin, next_xmax = xmin+(xmax-xmin)/2, xmax
  end
  if length(t)>1
    tree2cartesian(t[2:end], next_xmin, next_xmax, next_ymin, next_ymax)
  else
    return next_xmin, next_xmax, next_ymin, next_ymax
  end
end
