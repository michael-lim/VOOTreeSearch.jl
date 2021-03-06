##
# sparse sampling solvers

function estimate_v(opt::AbstractVSSOptions, m::Union{MDP,POMDP}, belief::AbstractVector, depth::Int, rng::AbstractRNG=Random.GLOBAL_RNG)
    if depth >= maxdepth(opt)
        return 0.0
    end

    a_list = Vector{Float64}[]
    q_list = Float64[]
    a_space = actions(m)

    for i in 1:max(floor(action_width(opt) * opt.action_width_decay^depth), 1)
        a = voo_sample(opt.voo, a_list, q_list, a_space)
        push!(a_list, a)
        push!(q_list, estimate_q(opt, m, belief, a, depth))
        if depth + 1 >= maxdepth(opt) && opt.last_action_null
            break
        end
    end
    return maximum(q_list)
end

# VOSS solver - Not tested
function estimate_q(opt::VOSSOptions, m::MDP, belief::AbstractVector, a, depth::Int, rng::AbstractRNG=Random.GLOBAL_RNG)
    qsum = 0.0
    children = Dict{obstype(m), Vector{statetype(m)}}()

    for i in 1:width(opt)
        s = belief[i]
        if !isterminal(m, s)
            sp, o, r = gen(m, s, a, rng)
            vp = estimate_v(opt, m, sp, depth+1)
            qsum += r + discount(m) * vp
        end
    end
    return qsum / width(opt)
end

function valuepairs(p::VSSPlanner{M}, b) where M <: POMDP
    belief = collect(rand(p.rng, b) for i in 1:p.opt.width)
    a_list = Vector{Float64}[]
    q_list = Float64[]
    a_space = actions(p.m)
    
    for i in 1:action_width(p.opt)
        a = voo_sample(p.opt.voo, a_list, q_list, a_space)
        push!(a_list, a)
        push!(q_list, estimate_q(p.opt, p.m, belief, a, 0))
    end
    return (a_list[i]=>q_list[i] for i in 1:action_width(p.opt)) 
end

function POMDPs.action(p::VSSPlanner{M}, b) where M <:POMDP
    avps = collect(valuepairs(p, b))
    best = avps[1]
    for av in avps[2:end]
        if last(av) > last(best)
            best = av
        end
    end
    return first(best)
end

# VOWSS solver
function estimate_q(opt::VOWSSOptions, m::POMDP, belief::AbstractVector, a, depth::Int, rng::AbstractRNG=Random.GLOBAL_RNG)
    q = 0.0
    
    predictions = Vector{statetype(m)}(undef, opt.width)
    observations = Vector{obstype(m)}(undef, opt.width)

    allterminal = true
    wsum = 0.0
    for i in 1:width(opt)
        s, w = weighted_state(belief, i)
        if !isterminal(m, s)
            allterminal = false
            sp, o, r = gen(m, s, a, rng)
            predictions[i] = sp
            observations[i] = o
            q += w * r
        end
        wsum += w
    end

    if allterminal
        return 0.0
    elseif depth + 1 >= maxdepth(opt)
        return q/wsum
    end

    nextbelief = Vector{Pair{statetype(m), Float64}}(undef, opt.width)

    for i in 1:width(opt) # needs to be a separate for loop because it needs all predictions
        s, ow = weighted_state(belief, i)
        if !isterminal(m, s)
            o = observations[i]
            for j in 1:width(opt)
                s, w = weighted_state(belief, j)
                if isterminal(m, s)
                    nextbelief[j] = s=>0.0
                else
                    sp = predictions[j]
                    nextbelief[j] = sp=>w * obs_weight(m, s, a, sp, o)
                end
            end
            vp = estimate_v(opt, m, nextbelief, depth+1)
            q += ow * discount(m) * vp
        end
    end
    return q/wsum
end

weighted_state(b::AbstractVector, i) = b[i]=>1/length(b)
weighted_state(b::AbstractVector{Pair{S,Float64}}, i) where {S} = b[i]