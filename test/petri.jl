f = PetriCospan(
        Cospan(FinOrdFunction([1,2], 2, 4),
               FinOrdFunction([3,4], 2, 4)
        ), id(PetriFunctor), Petri.Model([1, 2, 3, 4], [(Dict(1=>1), Dict(3=>1)), (Dict(2=>1), Dict(4=>1))]))

g = PetriCospan(
        Cospan(FinOrdFunction([1,2], 2, 3),
               FinOrdFunction([3], 1, 3)
        ), id(PetriFunctor), Petri.Model([1, 2, 3], [(Dict(1=>1, 2=>1), Dict(3=>1))]))

h = f ⋅ g

h′ = PetriCospan(
         Cospan(FinOrdFunction([1,2], 2, 5),
                FinOrdFunction([5], 1, 5)
         ), id(PetriFunctor), Petri.Model([1, 2, 3, 4, 5],
                                          [(Dict(1=>1), Dict(3=>1)), (Dict(2=>1), Dict(4=>1)), (Dict(3=>1, 4=>1), Dict(5=>1))]))

h_id = h ⋅ id(PetriCospanOb(1))

@test dom(f) == PetriCospanOb(2)
@test codom(f) == PetriCospanOb(2)
@test dom(g) == codom(f)
@test codom(g) == PetriCospanOb(1)
@test dom(h) == dom(f)
@test codom(h) == codom(g)

compare_petricospan(h, h′)
compare_petricospan(h, h_id)