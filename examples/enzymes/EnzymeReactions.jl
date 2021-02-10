module EnzymeReactions

using AlgebraicPetri
using Catlab.Programs
using Catlab.Graphics
using Catlab.WiringDiagrams
using Catlab.CategoricalAlgebra
using Distributions

using DifferentialEquations
using Plots

export ob, ode,
       inactivate, bindunbind, degrade,
       enzX, enzXY, enzXsubY,
       enz, enz_enz, enz_sub,
       enzyme_uwd

ob(type, x) = codom(Open([first(x)], LabelledReactionNet{type,Number}(x), [first(x)])).ob;

ode(x::Union{AbstractReactionNet{Distribution, Number},AbstractLabelledReactionNet{Distribution, Number}}, t) = begin
  β = mean.(rates(x))
  ODEProblem(vectorfield(x), concentrations(x), t, β)
end
ode(x, t) = ODEProblem(vectorfield(x), concentrations(x), t, rates(x));

function inactivate(in,on::T) where T
  inact = Symbol(first(in), :inact)
  Open(LabelledReactionNet{T,Number}(unique((in, inact=>0)), ((Symbol(:inact_,first(in)),on),first(in)=>inact)))
end;

function bindunbind(in1, in2, on::T, off::T) where T
  out = Symbol(first(in1),first(in2))
  Open(LabelledReactionNet{T,Number}(unique((in1, in2,out=>0)), ((Symbol(:bind_,first(in1),first(in2)),on),(first(in1),first(in2))=>out),
                                                                ((Symbol(:unbind_,out),off),out=>(first(in1),first(in2)))))
end;

function degrade(prod1,prod2,on::T) where T
  in = Symbol(first(prod1),first(prod2))
  prod2str = String(first(prod2))
  degprod2 = Symbol(endswith(prod2str, "inact") ? first(prod2str) : prod2str, :deg)
  Open(LabelledReactionNet{T,Number}(unique((in=>0, prod1,degprod2=>0)), ((Symbol(:deg_,in),on),in=>(first(prod1),degprod2))));
end;

# ## Cathepsin *X* reacting with itself

enzX = @relation (X, Xinact, Xdeg) where (X, Xinact, Xdeg, XX, XXinact) begin
  inactX(X, Xinact)
  bindXX(X, XX)
  degXX(XX, X, Xdeg)
  bindXXinact(X, Xinact, XXinact)
  degXXinact(XXinact, X, Xdeg)
end

# ## Cathepsin *X* reacting with Substrate *Y*

enzXsubY = @relation (X, Xinact, Xdeg, Y, Ydeg) where (X, Xinact, Xdeg, Y, XY, Ydeg) begin
  bindXY(X, Y, XY)
  degXY(XY, X, Ydeg)
end

# ## Cathepsin *X* reacting with Cathepsin *Y*

enzXY = @relation (X, Xinact, Xdeg, Y, Yinact, Ydeg) where (X, Xinact, Xdeg, Y, Yinact, Ydeg, XY, XYinact) begin
  bindXY(X, Y, XY)
  degXY(XY, X, Ydeg)
  bindXYinact(X, Yinact, XYinact)
  degXYinact(XYinact, X, Ydeg)
end

function enz(rxns, cat)
  catsym = first(cat)
  obtype = valtype(rates(apex(first(last(first(rxns))))))
  out = oapply(enzX, Dict([:inactX, :bindXX, :degXX, :bindXXinact, :degXXinact] .=> rxns[catsym]), Dict(
    :X=>ob(obtype, cat),
    :Xinact=>ob(obtype, Symbol(catsym,:inact)=>0),
    :Xdeg=>ob(obtype, Symbol(catsym,:deg)=>0),
    :XX=>ob(obtype, Symbol(catsym,catsym)=>0),
    :XXinact=>ob(obtype, Symbol(catsym,catsym,:inact)=>0)))
  bundle_legs(out, [[1,2,3]])
end

function enz_sub(rxns, cat1, sub)
  catsym = first(cat1)
  subsym = first(sub)
  catsub = Symbol(catsym, subsym)
  obtype = valtype(rates(apex(first(last(first(rxns))))))
  out = oapply(enzXsubY, Dict([:bindXY, :degXY] .=> rxns[catsub]), Dict(
    :X=>ob(obtype, cat1),
    :Xinact=>ob(obtype, Symbol(catsym,:inact)=>0),
    :Xdeg=>ob(obtype, Symbol(catsym,:deg)=>0),
    :Y=>ob(obtype, sub),
    :XY=>ob(obtype, Symbol(catsym,subsym)=>0),
    :Ydeg=>ob(obtype, Symbol(subsym,:deg)=>0)))
  bundle_legs(out, [[1,2,3], [4,5]])
end

function enz_enz(rxns, cat1, cat2)
  cat1sym = first(cat1)
  cat2sym = first(cat2)
  catcat = Symbol(cat1sym, cat2sym)
  obtype = valtype(rates(apex(first(last(first(rxns))))))
  out = oapply(enzXY, Dict([:bindXY, :degXY, :bindXYinact, :degXYinact] .=> rxns[catcat]), Dict(
    :X=>ob(obtype, cat1),
    :Xinact=>ob(obtype, Symbol(cat1sym,:inact)=>0),
    :Xdeg=>ob(obtype, Symbol(cat1sym,:deg)=>0),
    :Y=>ob(obtype, cat2),
    :Yinact=>ob(obtype, Symbol(cat2sym,:inact)=>0),
    :Ydeg=>ob(obtype, Symbol(cat2sym,:deg)=>0),
    :XY=>ob(obtype, catcat=>0),
    :XYinact=>ob(obtype, Symbol(catcat,:inact)=>0)))
  bundle_legs(out, [[1,2,3], [4,5,6]])
end

function enzyme_uwd(enzymes::Array{Symbol}, substrates::Array{Symbol})
  rel = RelationDiagram{Symbol}(0)

  chemicals = vcat(substrates, enzymes)

  subs = add_junctions!(rel, length(substrates), variable=substrates)
  enzs = add_junctions!(rel, length(enzymes), variable=enzymes)
  nsubs = length(subs)
  nenzs = length(enzs)

  catx = add_parts!(rel, :Box, nenzs, name=[Symbol("cat$i") for i in enzymes])
  add_parts!(rel, :Port, nenzs, junction=enzs, box=catx)

  for x in 1:nenzs
    for y in 1:nenzs
      if y != x
        catxy = add_part!(rel, :Box, name=Symbol("cat$(enzymes[x])cat$(enzymes[y])"))
        add_parts!(rel, :Port, 2, junction=[enzs[x], enzs[y]], box=catxy)
      end
    end
  end

  for x in 1:nenzs
    for y in 1:nsubs
      catxy = add_part!(rel, :Box, name=Symbol("cat$(enzymes[x])sub$(substrates[y])"))
      add_parts!(rel, :Port, 2, junction=[enzs[x], subs[y]], box=catxy)
    end
  end
  add_parts!(rel, :OuterPort, length(chemicals), outer_junction = vcat(subs, enzs))
  rel
end

end