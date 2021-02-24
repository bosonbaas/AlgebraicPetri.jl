module Estimators

using AlgebraicPetri
using AlgebraicPetri.Epidemiology
using Catlab.CategoricalAlgebra

using DifferentialEquations
using MCMCChains
using Turing, Distributions

import Turing: sample
export estimate_rates, sample, meanRates

Turing.setadbackend(:forwarddiff)

# API DEVELOPMENT

# ========
# = GOAL =
# ========

# data = ...
# tspan = (1, 180)
# rxn = enzyme_reaction([:K, :L], [:E])
# pred_rates = estimate_rates(rxn, tspan, data)
# tuned_rxn = LabelledReactionNet{Number, Number}(rxn, [], meanRates(pred_rates))
# prob = ODEProblem(tuned_rxn, tspan)
# plot(solve(prob))
# scatter!(data)

# ============
# = API CODE =
# ============

function estimate_rates(rxn::AbstractLabelledReactionNet, j_data; kw...)
  tspan = j_data["time_data"]
  data = j_data["data"]
  d_keys = collect(keys(data))
  estimate_rates(rxn, tspan, Symbol.(d_keys)=>collect(vcat([data[k]' for k in d_keys]...)); kw...)
end

function estimate_rates(rxn::Union{AbstractReactionNet, AbstractLabelledReactionNet}, tspan, data; kw...)
  estimate_rates(rxn, tspan, rates(rxn), data; kw...)
end

function estimate_rates(rxn::Union{AbstractReactionNet, AbstractLabelledReactionNet}, tspan, data; kw...)
  estimate_rates(rxn, tspan, rates(rxn), data; kw...)
end

function estimate_rates(rxn::AbstractReactionNet, tspan, priors, data; iter_method=PG(10, 100), sample_steps=1000,
                                                                       error_scale=x->x, param_scale=x->x,
                                                                       error_dist = InverseGamma(1,1))
  data[2] .= error_scale.(data[2])
  est_prob = EstimationProblem(rxn, tspan, priors, data, error_scale, param_scale, error_dist)
  sample(est_prob, iter_method, sample_steps)
end

function estimate_rates(rxn::AbstractLabelledReactionNet{X,Y}, tspan, priors, data; kw...) where {X, Y}
  tnames = subpart(rxn, :tname)
  snames = subpart(rxn, :sname)
  tname_ind = Dict(tnames[i]=>i for i in 1:length(tnames))
  sname_ind = Dict(snames[i]=>i for i in 1:length(snames))
  new_priors = [priors[t] for t in tnames]
  new_data = [sname_ind[k] for k in data[1]]=>data[2]
  pred = estimate_rates(ReactionNet{X,Y}(rxn), tspan, new_priors, new_data; kw...)
  replacenames(pred, [Symbol("p[$i]")=>tnames[i] for i in 1:length(tnames)]...)
end

struct EstimationProblem
  petri::AbstractPetriNet
  tspan
  priors
  data
  u0
  error_scale::Function
  param_scale::Function
  error_dist::Distribution
end

function EstimationProblem(rxn::Union{AbstractReactionNet,AbstractLabelledReactionNet},
                           tspan, priors, data, error_scale, param_scale, error_dist)
  EstimationProblem(rxn, tspan, priors, data, concentrations(rxn), error_scale, param_scale, error_dist)
end

function turing_model(prob::EstimationProblem)
  @model function fit_fun(data_idxs, data, prob′)
    σ ~ prob.error_dist

    # pick distribution with possible range of parameters
    p ~ product_distribution(prob.priors)

    prob′′ = remake(prob′,p=prob.param_scale.(p))
    predicted = solve(prob′′,saveat=prob.tspan)

    # modify for data format
    for i = 1:length(prob.tspan)
      for (j,s) in enumerate(data_idxs)
        data[j,i] ~ Normal(prob.error_scale(predicted(prob.tspan[i])[s]), σ)
      end
    end
  end
  fit_fun(prob.data..., ODEProblem(vectorfield(prob.petri), prob.u0, (minimum(prob.tspan), maximum(prob.tspan)), rates(prob.petri)))
end

sample(prob::EstimationProblem, args...) = sample(turing_model(prob), args...)

meanRates(pred::Chains) = filter(x->x.first != :σ, Dict(zip(mean(pred).nt.parameters, mean(pred).nt.mean)))
end
