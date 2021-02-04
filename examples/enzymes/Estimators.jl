module Estimators

using AlgebraicPetri
using AlgebraicPetri.Epidemiology
using Catlab.CategoricalAlgebra

using DifferentialEquations
using MCMCChains
using Turing, Distributions

import Turing: sample
export estimate_rates

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

function estimate_rates(rxn::Union{AbstractReactionNet, AbstractLabelledReactionNet}, tspan, data; kw...)
  estimate_rates(rxn, tspan, rates(rxn), data; kw...)
end

function estimate_rates(rxn::AbstractReactionNet, tspan, priors, data; mc_stepsize=0.01, mc_leapfrogsteps=5, sample_steps=1000)
  est_prob = EstimationProblem(rxn, tspan, priors, data; kw...)
  sample(est_prob, HMC(mc_stepsize, mc_leapfrogsteps), sample_steps)
end

function estimate_rates(rxn::AbstractLabelledReactionNet{X,Y}, tspan, priors, data; kw...) where {X, Y}
  tnames = subpart(rxn, :tname)
  snames = subpart(rxn, :sname)
  tname_ind = Dict(tnames[i]=>i for i in 1:length(tnames))
  sname_ind = Dict(snames[i]=>i for i in 1:length(snames))
  pred = estimate_rates(ReactionNet{X,Y}(rxn), tspan, [priors[t] for t in tnames], [sname_ind[k] for k in data[1]]=>data[2]; kw...)
  replacenames(pred, [Symbol("p[$i]")=>tnames[i] for i in 1:length(tnames)]...)
end

struct EstimationProblem
  petri::AbstractPetriNet
  tspan
  priors
  data
  u0
end

function EstimationProblem(rxn::Union{AbstractReactionNet,AbstractLabelledReactionNet}, tspan, priors, data)
  EstimationProblem(rxn, tspan, priors, data, concentrations(rxn))
end

function turing_model(prob::EstimationProblem)
  @model function fit_fun(data_idxs, data, prob′)
    σ ~ InverseGamma(2,3)

    # pick distribution with possible range of parameters
    p ~ product_distribution(prob.priors)

    prob′′ = remake(prob′,p=p)
    predicted = solve(prob′′,Tsit5(),saveat=0.1)

    # modify for data format
    for i = 1:length(predicted)
      for (j,s) in enumerate(data_idxs)
        data[j,i] ~ Normal(predicted[i][s], σ)
      end
    end
  end
  fit_fun(prob.data..., ODEProblem(vectorfield(prob.petri), prob.u0, prob.tspan, rates(prob.petri)))
end

sample(prob::EstimationProblem, args...) = sample(turing_model(prob), args...)
end