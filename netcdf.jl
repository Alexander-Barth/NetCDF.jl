module ncdf
using Base
export show,NcDim,NcVar,NcFile,open
#Some constants
NC_NOERR=0
NC_MAX_NAME=256
NC_VERBOSE=true


const NC_CHAR =2
NC_SHORT =3
NC_INT =4
NC_FLOAT=5
NC_DOUBLE =6
NC_GLOBAL=-1
NC_CLOBBER=0x0000
NC_NOCLOBBER=0x0004


jltype2nctype={Int16=>NC_SHORT,
               Int32=>NC_INT,
               Float32=>NC_FLOAT,
               Float64=>NC_DOUBLE}


type NcDim
  ncid::Integer
  dimid::Integer
  varid::Integer
  name::String
  dimlen::Integer
  vals::AbstractArray
  atts::Dict{Any,Any}
end
NcDim(name::String,vals::Union(AbstractArray,Number),atts::Dict{Any,Any})=NcDim(-1,-1,-1,name,length(vals),vals,atts)
NcDim(name::String,vals::Union(AbstractArray,Number))=NcDim(name,vals,{"units"=>"unknown"})

type NcVar
  ncid::Integer
  varid::Integer
  ndim::Integer
  natts::Integer
  nctype::Integer
  name::String
  dimids::Array{Int}
  dim::Dict{Int,NcDim}
  atts::Dict{Any,Any}
end
function NcVar(name::String,dimin,atts::Dict{Any,Any},jltype::Type)
    i=0
    dim=Dict{Int,NcDim}()
    for d in dimin
      dim[i]=d
      i=i+1
    end
    return NcVar(-1,-1,length(dim),length(atts),jltype2nctype[jltype],name,Array(Int,length(dim)),dim,atts)
end


type NcFile
  ncid::Integer
  nvar::Integer
  ndim::Integer
  ngatts::Integer
  vars::Dict{Int,NcVar}
  dim::Dict{Int,NcDim}
  gatts::Dict{Any,Any}
  nunlimdimid::Integer
  name::String
end

  

function _cchartostring(in)
  iname=1
  name=""
  #println(in)
  if (length(in)>0)
    while (char(in[iname])!='\0' && iname<length(in))
      name=strcat(name,char(in[iname]))
      iname=iname+1
    end
  end
  return name
end


function _nc_op(fname::String)
  # Open netcdf file
  ida=Array(Int32,1)
  omode=0
  _nc_open_c(fname,omode,ida)
  id=ida[1]
  println("Successfully opened ",fname," dimid=",id)
  return id
end

function _nc_inq_dim(id::Integer,idim::Integer)
  namea=Array(Uint8,NC_MAX_NAME+1);lengtha=Array(Int32,1)
  _nc_inq_dim_c(id,idim,namea,lengtha)
  name=_cchartostring(namea)
  dimlen=lengtha[1]
  NC_VERBOSE ? println("Successfully read from file") : nothing
  NC_VERBOSE ? println("name=",name," dimlen=",dimlen) : nothing
  return (name,dimlen)
end

function _ncf_inq(id::Integer)
  # Inquire number of codes in netCDF file
  ndima=Array(Int32,1);nvara=Array(Int32,1);ngatta=Array(Int32,1);nunlimdimida=Array(Int32,1)
  _nc_inq_c(id,ndima,nvara,ngatta,nunlimdimida)
  ndim=ndima[1]
  nvar=nvara[1]
  ngatt=ngatta[1]
  nunlimdimid=nunlimdimida[1]
  NC_VERBOSE ? println("Successfully read from file") : nothing
  NC_VERBOSE ? println("ndim=",ndim," nvar=",nvar," ngatt=",ngatt," numlimdimid=",nunlimdimid) : nothing
  return (ndim,nvar,ngatt,nunlimdimid)
end

function _nc_inq_attname(ncid::Integer,varid::Integer,attnum::Integer)
  # Get attribute name from attribute number
  namea=Array(Uint8,NC_MAX_NAME+1)
  _nc_inq_attname_c(ncid,varid,attnum,namea)
  name=_cchartostring(namea)
  NC_VERBOSE ? println("Successfully read attribute name") : nothing
  NC_VERBOSE ? println("name=",name) : nothing
  return name
end


function _nc_inq_att(ncid::Integer,varid::Integer,attnum::Integer)
  # First get attribute name
  name=_nc_inq_attname(ncid,varid,attnum)
  NC_VERBOSE ? println(name) : nothing
  #Then find out about attribute
  typea=Array(Int32,1);nvals=Array(Int32,1)
  _nc_inq_att_c(ncid,varid,name,typea,nvals)
  attype=typea[1]
  NC_VERBOSE ? println("Successfully read attribute type and number of vals") : nothing
  NC_VERBOSE ? println("atttype=",attype," nvals=",nvals[1]) : nothing
  text=_nc_get_att(ncid,varid,name,attype,nvals[1])
  return (name,text)
end

function _nc_get_att(ncid::Integer,varid::Integer,name,attype::Integer,attlen::Integer)
  if (attype==NC_CHAR)
    valsa=Array(Uint8,attlen+5)
    _nc_get_att_text_c(ncid,varid,name,valsa)
    valsa=string(_cchartostring(valsa))
  elseif (attype==NC_SHORT)
    valsa=Array(Int16,attlen)
    _nc_get_att_short_c(ncid,varid,name,valsa)
  elseif (attype==NC_INT)
    valsa=Array(Int32,attlen)
    _nc_get_att_int_c(ncid,varid,name,valsa)
  elseif (attype==NC_FLOAT)
    valsa=Array(Float32,attlen)
    _nc_get_att_float_c(ncid,varid,name,valsa)
  elseif (attype==NC_DOUBLE)
    valsa=Array(Float64,attlen)
    _nc_get_att_double_c(ncid,varid,name,valsa)
  end
  return valsa
end

function _ncv_inq(nc::NcFile,varid::Integer)
  id=nc.ncid
  ndim=length(nc.dim)
  # Inquire variables in the file
  namea=Array(Uint8,NC_MAX_NAME+1);xtypea=Array(Int32,1);ndimsa=Array(Int32,1);dimida=Array(Int32,ndim);natta=Array(Int32,1)
  _nc_inq_var_c(id,varid,namea,xtypea,ndimsa,dimida,natta)
  println("dimida=",dimida," ndimsa=",ndimsa)
  nctype=xtypea[1]
  vndim=ndimsa[1]
  dimids=vndim>0 ? dimida[1:vndim] : []
  natts=natta[1]
  NC_VERBOSE ? println("Successfully read from file") : nothing
  name=_cchartostring(namea)
  isdimvar=false
  for n in nc.dim
    if (n[2].name==name)
      isdimvar=true
      break
    end
  end
  NC_VERBOSE ? println("name=",name," nctype=",nctype," dimids=",dimids," natts=",natts," vndim=",vndim) : nothing
  return (name,nctype,dimids,natts,vndim,isdimvar)
end

function _getvarindexbyname(nc::NcFile,varname::String)
  va=nothing
  for v in nc.vars
    va = v[2].name==varname ? v[2] : va
  end
  return va
end

function _getdimindexbyname(nc::NcFile,dimname::String)
  da=nothing
  for d in nc.dim
    da = d[2].name==dimname ? d[2] : da
  end
  return da.dimid
end

function _readdimdvar(ncid::Integer,dim::NcDim)
  start=0
  p=dim.dimlen
  #Determine size of Array
  retvalsa=Array(Float64,p)
  _nc_get_vara_double_c(ncid,varid,start,count,retvalsa)
  NC_VERBOSE ? println("Successfully read dimension from file ",dim.name) : nothing
  dim.vals=retvalsa
  end

# Read block of data from file
function readvar(nc::NcFile,varid::Integer,start::Array,count::Array)
  ncid=nc.ncid
  start=int64(start)-1
  count=int64(count)
  @assert nc.vars[varid].ndim==length(start)
  @assert nc.vars[varid].ndim==length(count)
  println(keys(nc.vars))
  for i = 1:length(count)
    count[i]= count[i]>0 ? count[i] : nc.vars[varid].dim[nc.vars[varid].dimids[i]].dimlen
  end
  #Determine size of Array
  p=1
  for i in count
    p=p*i
  end
  NC_VERBOSE ? println("$ncid $varid $p $count ${nc.vars[varid].nctype}") : nothing
  if nc.vars[varid].nctype==NC_DOUBLE
    retvalsa=Array(Float64,p)
    _nc_get_vara_double_c(ncid,varid,start,count,retvalsa)
  elseif nc.vars[varid].nctype==NC_FLOAT
    retvalsa=Array(Float64,p)
    _nc_get_vara_double_c(ncid,varid,start,count,retvalsa)
  elseif nc.vars[varid].nctype==NC_INT
    retvalsa=Array(Int32,p)
    _nc_get_vara_int_c(ncid,varid,start,count,retvalsa)
  elseif nc.vars[varid].nctype==NC_SHORT
    retvalsa=Array(Int32,p)
    _nc_get_vara_int_c(ncid,varid,start,count,retvalsa)
  elseif nc.vars[varid].nctype==NC_CHAR
    retvalsa=Array(Uint8,p)
    _nc_get_vara_text_c(ncid,varid,start,count,retvalsa)
  end
  NC_VERBOSE ? println("Successfully read from file ",ncid) : nothing
  if length(count)>1 
    return reshape(retvalsa,ntuple(length(count),x->count[x]))
  else
    return retvalsa
  end
end
function readvar(nc::NcFile,varid::String,start,count) 
  va=_getvarindexbyname(nc,varid)
  va == nothing ? error("Error: Variable $varid not found in $(nc.name)") : return readvar(nc,va.varid,start,count)
end
function readvar(nc::NcFile,varid::NcVar,start,count) 
  return readvar(nc,varid.varid,start,count)
end


function putvar(nc::NcFile,varid::Integer,start::Array,vals::Array)
  ncid=nc.ncid
  @assert nc.vars[varid].ndim==length(start)
  println(keys(nc.vars))
  coun=size(vals)
  count=Array(Int64,length(coun))
  start=int64(start)-1
  #Determine size of Array
  p=1
  for i in 1:length(coun)
    p=p*coun[i]
    count[i]=coun[i]
  end
  NC_VERBOSE ? println("$ncid $varid $p $count ",nc.vars[varid].nctype) : nothing
  #x=reshape(vals,p)
  x=vals
  if nc.vars[varid].nctype==NC_DOUBLE
    _nc_put_vara_double_c(ncid,varid,start,count,x)
  elseif nc.vars[varid].nctype==NC_FLOAT
    _nc_put_vara_double_c(ncid,varid,start,count,x)
  elseif nc.vars[varid].nctype==NC_INT
    _nc_put_vara_int_c(ncid,varid,start,count,x)
  elseif nc.vars[varid].nctype==NC_SHORT
    _nc_put_vara_int_c(ncid,varid,start,count,x)
  elseif nc.vars[varid].nctype==NC_CHAR
    _nc_put_vara_text_c(ncid,varid,start,count,x)
  end
  NC_VERBOSE ? println("Successfully wrote to file ",ncid) : nothing
end
function putvar(nc::NcFile,varid::String,start,vals) 
  va=_getvarindexbyname(nc,varid)
  va == nothing ? error("Error: Variable $varid not found in $(nc.name)") : return putvar(nc,va.varid,start,vals)
end


function new(name::String,varlist::Union(Array{NcVar},NcVar))
  ida=Array(Int32,1)
  vars=Dict{Int,NcVar}();
  #Create the file
  _nc_create_c(name,NC_CLOBBER,ida);
  id=ida[1];
  # Unify types
  if (typeof(varlist)==NcVar)
    varlist=[varlist]
  end
  # Collect Dimensions
  dims=Set{NcDim}();
  for v in varlist
    for d in v.dim
      add!(dims,d[2]);
    end
  end
  nunlim=0;
  ndim=int32(length(dims));
  #Create Dimensions in the file
  dim=Dict{Int,NcDim}();
  for d in dims
    dima=Array(Int32,1);
    println("Dimension length ", d.dimlen)
    _nc_def_dim_c(id,d.name,d.dimlen,dima);
    d.dimid=dima[1];
    dim[d.dimid]=d;
    #Create dimension variable
    varida=Array(Int32,1)
    _nc_def_var_c(id,d.name,NC_DOUBLE,1,[d.dimid],varida)
    d.varid=varida[1]
    dd=Dict{Int,NcDim}()
    dd[d.dimid]=d
    vars[varida[1]]=NcVar(id,varida[1],1,length(d.atts),NC_DOUBLE,d.name,int([d.dimid]),dd,d.atts)
  end
  # Create variables in the file
  for v in varlist
    i=1
    for d in v.dim
      v.dimids[i]=d[2].dimid
      i=i+1
    end
    vara=Array(Int32,1);
    println("dimids=",v.dimids)
    _nc_def_var_c(id,v.name,v.nctype,v.ndim,[v.dimids],vara);
    v.varid=vara[1];
    vars[v.varid]=v;
  end
  # Leave define mode
  _nc_enddef_c(id)
  #Write dimension variables
  for d in dims
    #Write dimension variable
    y=float64(d.vals)
    diml=d.dimlen
    _nc_put_vara_double_c(id,d.varid,[0],[diml],y)
  end
  #Create the NcFile Object
  nc=NcFile(id,length(vars),ndim,0,vars,dim,Dict{Any,Any}(),0,name)
end

function close(nco::NcFile)
  #Close file
  _nc_close_c(nco.ncid) 
  println("Successfully closed file ",nco.ncid)
  return nco.ncid
end

function _nc_getatts_all(ncid::Integer,varid::Integer,natts::Integer)
  atts=Dict{Any,Any}()
  for attnum=0:natts-1
    gatt=_nc_inq_att(ncid,varid,attnum)
    atts[gatt[1]]=string(gatt[2])
  end
  NC_VERBOSE ? println(atts) : nothing
  return atts
end

function _readdimvars(nc::NcFile)
  for d in nc.dim
    for v in nc.vars
      if (d[2].name==v[2].name)
        println(d[2].name," ",v[2].name)
        d[2].vals=readvar(nc,v[2].varid,[1],[-1])
        d[2].atts=v[2].atts
      end
    end
  end
end


function open(fil::String)
  # Open netcdf file
  ncid=_nc_op(fil)
  NC_VERBOSE ? println(ncid) : nothing
  #Get initial information
  (ndim,nvar,ngatt,nunlimdimid)=_ncf_inq(ncid)
  NC_VERBOSE ? println(ndim,nvar,ngatt,nunlimdimid) : nothing
  #Create ncdf object
  ncf=NcFile(ncid,nvar-ndim,ndim,ngatt,Dict{Int,NcVar}(),Dict{Int,NcDim}(),Dict{Any,Any}(),nunlimdimid,fil)
  #Read global attributes
  ncf.gatts=_nc_getatts_all(ncid,NC_GLOBAL,ngatt)
  #Read dimensions
  for dimid = 0:ndim-1
    (name,dimlen)=_nc_inq_dim(ncid,dimid)
    ncf.dim[dimid]=NcDim(ncid,dimid,-1,name,dimlen,[1:dimlen],Dict{Any,Any}())
  end
  #Read variable information
  for varid = 0:nvar-1
    (name,nctype,dimids,natts,vndim,isdimvar)=_ncv_inq(ncf,varid)
    if (isdimvar)
      ncf.dim[_getdimindexbyname(ncf,name)].varid=varid
    end
    atts=_nc_getatts_all(ncid,varid,natts)
    vdim=Dict{Int,NcDim}()
    for did in dimids
      vdim[did]=ncf.dim[did]
    end
    ncf.vars[varid]=NcVar(ncid,varid,vndim,natts,nctype,name,int(dimids),vdim,atts)
    end
  end
  _readdimvars(ncf)
  ncf
end

function quickread(fil::String)
  nc=open(fil)
  nc.nvar!=1 ? error("Error, number of variables not equal to 1") : nothing
  iv=nothing
  for v in nc.vars
    iv=v[2].varid
  end
  s=ones(Int,nc.vars[iv].ndim)
  c=s*(-1)
  x=readvar(nc,iv,s,c)
  close(nc)
  return x
end


function show(nc::NcFile)
  println("File: ",nc.name)
  println("Number of variables: ",nc.nvar)
end

#
#  CCall wrapper functions, thanks to TimHoly, copied from the HDF5-package
#
#
#
const libnetcdf = dlopen("libnetcdf")

function ccallexpr(ccallsym::Symbol, outtype, argtypes::Tuple, argsyms::Tuple)
    ccallargs = Any[expr(:quote, ccallsym), outtype, expr(:tuple, Any[argtypes...])]
    ccallargs = ccallsyms(ccallargs, length(argtypes), argsyms)
    expr(:ccall, ccallargs)
end

function ccallexpr(lib::Ptr, ccallsym::Symbol, outtype, argtypes::Tuple, argsyms::Tuple)
    ccallargs = Any[expr(:call, Any[:dlsym, lib, expr(:quote, ccallsym)]), outtype, expr(:tuple, Any[argtypes...])]
    ccallargs = ccallsyms(ccallargs, length(argtypes), argsyms)
    expr(:ccall, ccallargs)
end

function ccallsyms(ccallargs, n, argsyms)
    if n > 0
        if length(argsyms) == n
            ccallargs = Any[ccallargs..., argsyms...]
        else
            for i = 1:length(argsyms)-1
                push(ccallargs, argsyms[i])
            end
            for i = 1:n-length(argsyms)+1
                push(ccallargs, expr(:ref, argsyms[end], i))
            end
        end
    end
    ccallargs
end

function funcdecexpr(funcsym, n::Int, argsyms)
    if length(argsyms) == n
        return expr(:call, Any[funcsym, argsyms...])
    else
        exargs = Any[funcsym, argsyms[1:end-1]...]
        push(exargs, expr(:..., argsyms[end]))
        return expr(:call, exargs)
    end
end

# Functions returning a single argument, and/or with more complex
# error messages
for (jlname, h5name, outtype, argtypes, argsyms, ex_error) in
    ( (:_nc_open_c, :nc_open, Int32, (Ptr{Uint8}, Int32, Ptr{Int32}), (:fname,:omode,:ida), :(error("Error Opening file ", fname))),
      (:_nc_inq_dim_c,:nc_inq_dim,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Int32}),(:id,:idim,:namea,:lengtha),:(error("Error inquiring dimension information"))),
      (:_nc_inq_c,:nc_inq,Int32,(Int32,Ptr{Int32},Ptr{Int32},Ptr{Int32},Ptr{Int32}),(:id,:ndima,:nvara,:ngatta,:nunlimdimida),:(error("Error inquiring file information"))),
      (:_nc_inq_attname_c,:nc_inq_attname,Int32,(Int32,Int32,Int32,Ptr{Uint8}),(:ncid,:varid,:attnum,:namea),:(error("Error inquiring attribute name"))),
      (:_nc_inq_att_c,:nc_inq_att,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Int32},Ptr{Int32}),(:ncid,:varid,:name,:typea,:nvals),:(error("Error inquiring attribute properties"))),
      (:_nc_get_att_text_c,:nc_get_att_text,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Uint8}),(:ncid,:varid,:name,:valsa),:(error("Error reading attribute"))),
      (:_nc_get_att_short_c,:nc_get_att_short,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Int16}),(:ncid,:varid,:name,:valsa),:(error("Error reading attribute"))),
      (:_nc_get_att_int_c,:nc_get_att_int,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Int32}),(:ncid,:varid,:name,:valsa),:(error("Error reading attribute"))),
      (:_nc_get_att_float_c,:nc_get_att_float,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Float32}),(:ncid,:varid,:name,:valsa),:(error("Error reading attribute"))),
      (:_nc_get_att_double_c,:nc_get_att_double,Int32,(Int32,Int32,Ptr{Uint8},Ptr{Float64}),(:ncid,:varid,:name,:valsa),:(error("Error reading attribute"))),
      (:_nc_inq_var_c,:nc_inq_var,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Int32},Ptr{Int32},Ptr{Int32}),(:id,:varid,:namea,:xtypea,:ndimsa,:dimida,:natta),:(error("Error reading variable information"))),
      
      (:_nc_get_vara_double_c,:nc_get_vara_double,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Float64}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error reading variable"))),
      (:_nc_get_vara_int_c,:nc_get_vara_int,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Int32}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error reading variable"))),
      (:_nc_get_vara_short_c,:nc_get_vara_short,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Int16}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error reading variable"))),
      (:_nc_get_vara_text_c,:nc_get_vara_text,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Uint8}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error reading variable"))),
      
      (:_nc_put_vara_text_c,:nc_put_vara_text,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Uint8}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error writing variable"))),
      (:_nc_put_vara_double_c,:nc_put_vara_double,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Float64}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error writing variable"))),
      (:_nc_put_vara_float_c,:nc_put_vara_float,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Float32}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error writing variable"))),
      (:_nc_put_vara_int_c,:nc_put_vara_int,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Int32}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error writing variable"))),
      (:_nc_put_vara_short_c,:nc_put_vara_short,Int32,(Int32,Int32,Ptr{Int32},Ptr{Int32},Ptr{Int16}),(:ncid,:varid,:start,:count,:retvalsa),:(error("Error writing variable"))),
      (:_nc_close_c,:nc_close,Int32,(Int32,),(:ncid,),:(error("Error closing variable"))),
      (:_nc_enddef_c,:nc_enddef,Int32,(Int32,),(:ncid,),:(error("Error leaving define mode"))),
      (:_nc_create_c,:nc_create,Int32,(Ptr{Uint8},Int32,Ptr{Int32}),(:path,:comde,:ncida),:(error("Error creating netcdf file"))),
      (:_nc_def_dim_c,:nc_def_dim,Int32,(Int32,Ptr{Uint8},Int32,Ptr{Int32}),(:ncid,:name,:len,:dimida),:(error("Error creating dimension"))),
      (:_nc_def_var_c,:nc_def_var,Int32,(Int32,Ptr{Uint8},Int32,Int32,Ptr{Int32},Ptr{Int32}),(:ncid,:name,:xtype,:ndims,:dimida,:varida),:(error("Error creating variable"))),
     )
     
     
    
    ex_dec = funcdecexpr(jlname, length(argtypes), argsyms)
    ex_ccall = ccallexpr(libnetcdf, h5name, outtype, argtypes, argsyms)
    ex_body = quote
        ret = $ex_ccall
        if ret != 0
            println(ret)
            $ex_error
        end
        return ret
    end
    ex_func = expr(:function, Any[ex_dec, ex_body])
    @eval begin
        $ex_func
    end
end


end # Module