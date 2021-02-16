function dijkstra(net::Network, s::Int64, t::Int64)
    @unpack DIST, TIME_REV = net
    @unpack m, colptr, rowval, nzval = TIME_REV
    c = ones(Float64, m) * Inf
    p = zeros(Int64, m)
    T = zeros(Int64, m)
    L = zeros(Int64, m)
    c[s] = 0
    T[1] = s
    L[s] = 1
    n = 1
    while n > 0
        u = T[1]
        if u == t
            break
        end
        n_top = T[n]
        T[1] = n_top
        L[n_top] = 1
        n -= 1
        k = 1
        kt = n_top
        while true
            i = 2 * k
            if i > n
                break
            end
            if i == n
                it = T[i]
            else
                lc = T[i]
                rc = T[i+1]
                if c[lc] < c[rc]
                    it = lc
                else
                    it = rc
                    i += 1
                end
            end
            if c[kt] < c[it]
                break
            else
                T[k] = it
                L[it] = k
                T[i] = kt
                L[kt] = i
                k = i
            end
        end
        for ei = colptr[u]:(colptr[u + 1] - 1)
            v = rowval[ei]
            x = c[u] + nzval[ei]
            if c[v] > x
                c[v] = x
                p[v] = u
                k = L[v]
                if k == 0
                    n += 1
                    T[n] = v
                    L[v] = n
                    k = n
                    kt = v
                    onlyup = true
                else
                    kt = T[k]
                    onlyup = false
                end
                while !onlyup
                    i = 2 * k
                    if i > n
                        break
                    end
                    if i == n
                        it = T[i]
                    else
                        lc = T[i]
                        rc = T[i+1]
                        if c[lc] < c[rc]
                            it = lc
                        else
                            it = rc
                            i += 1
                        end
                    end
                    if c[kt] < c[it]
                        break
                    else
                        T[k] = it
                        L[it] = k
                        T[i] = kt
                        L[kt] = i
                        k = i
                    end
                end
                j = k
                tj = T[k]
                while j > 1
                    j2 = round(Int64,floor(j/2))
                    tj2 = T[j2]
                    if c[tj2] < c[tj]
                        break
                    else
                        T[j2] = tj
                        L[tj] = j2
                        T[j] = tj2
                        L[tj2] = j
                        j = j2
                    end
                end
            end
        end
    end
    v = t
    u = p[t]
    d = 0.0
    while !iszero(u)
        d += DIST[u,v]
        v = u
        u = p[v]
    end
    return Route(c[t]/60.0, d * ENERGY_PER_DISTANCE, [s,t])
end

function dijkstra_nearest_taxi_to_source(net::Network, s::Vector{Int64}, t::Int64, a::Vector{Float64})
    @unpack DIST, TIME = net
    @unpack m, colptr, rowval, nzval = TIME
    c = ones(Float64, m) * Inf
    d = ones(Float64, m) * Inf
    p = zeros(Int64, m)
    T = zeros(Int64, m)
    L = zeros(Int64, m)
    c[t] = 0
    d[t] = 0
    T[1] = t
    L[t] = 1
    n = 1
    ind = nothing
    len_s = length(s)
    count = 0
    while n > 0
        u = T[1]
        inds = findall(s .== u)
        len_inds = length(inds)
        for i = 1:len_inds
            if a[i] > d[u]
                ind = inds[i]
                break
            end
        end
        if !isnothing(ind)
            break
        end
        count += len_inds
        if count == len_s
            return nothing, nothing
        end
        n_top = T[n]
        T[1] = n_top
        L[n_top] = 1
        n -= 1
        k = 1
        kt = n_top
        while true
            i = 2 * k
            if i > n
                break
            end
            if i == n
                it = T[i]
            else
                lc = T[i]
                rc = T[i+1]
                if c[lc] < c[rc]
                    it = lc
                else
                    it = rc
                    i += 1
                end
            end
            if c[kt] < c[it]
                break
            else
                T[k] = it
                L[it] = k
                T[i] = kt
                L[kt] = i
                k = i
            end
        end
        for ei = colptr[u]:(colptr[u + 1] - 1)
            v = rowval[ei]
            x = c[u] + nzval[ei]
            if c[v] > x
                c[v] = x
                d[v] = d[u] + DIST[u,v]
                p[v] = u
                k = L[v]
                if k == 0
                    n += 1
                    T[n] = v
                    L[v] = n
                    k = n
                    kt = v
                    onlyup = true
                else
                    kt = T[k]
                    onlyup = false
                end
                while !onlyup
                    i = 2 * k
                    if i > n
                        break
                    end
                    if i == n
                        it = T[i]
                    else
                        lc = T[i]
                        rc = T[i+1]
                        if c[lc] < c[rc]
                            it = lc
                        else
                            it = rc
                            i += 1
                        end
                    end
                    if c[kt] < c[it]
                        break
                    else
                        T[k] = it
                        L[it] = k
                        T[i] = kt
                        L[kt] = i
                        k = i
                    end
                end
                j = k
                tj = T[k]
                while j > 1
                    j2 = round(Int64,floor(j/2))
                    tj2 = T[j2]
                    if c[tj2] < c[tj]
                        break
                    else
                        T[j2] = tj
                        L[tj] = j2
                        T[j] = tj2
                        L[tj2] = j
                        j = j2
                    end
                end
            end
        end
    end
    s_ind = s[ind]
    v = s_ind
    u = p[v]
    while !iszero(u)
        v = u
        u = p[v]
    end
    return ind, Route(c[s_ind] / 60.0, d[s_ind] * ENERGY_PER_DISTANCE, [s_ind,t])
end

function dijkstra_taxi_to_nearest_charger(net::Network, s::Int64, t::Vector{Int64})::Tuple{Int64,Route}
    @unpack DIST, TIME_REV = net
    @unpack m, colptr, rowval, nzval = TIME_REV
    c = ones(Float64, m) * Inf
    p = zeros(Int64, m)
    T = zeros(Int64, m)
    L = zeros(Int64, m)
    c[s] = 0
    T[1] = s
    L[s] = 1
    n = 1
    ind = nothing
    while n > 0
        u = T[1]
        ind = findfirst(t .== u)
        if !isnothing(ind)
            break
        end
        n_top = T[n]
        T[1] = n_top
        L[n_top] = 1
        n -= 1
        k = 1
        kt = n_top
        while true
            i = 2 * k
            if i > n
                break
            end
            if i == n
                it = T[i]
            else
                lc = T[i]
                rc = T[i+1]
                if c[lc] < c[rc]
                    it = lc
                else
                    it = rc
                    i += 1
                end
            end
            if c[kt] < c[it]
                break
            else
                T[k] = it
                L[it] = k
                T[i] = kt
                L[kt] = i
                k = i
            end
        end
        for ei = colptr[u]:(colptr[u + 1] - 1)
            v = rowval[ei]
            x = c[u] + nzval[ei]
            if c[v] > x
                c[v] = x
                p[v] = u
                k = L[v]
                if k == 0
                    n += 1
                    T[n] = v
                    L[v] = n
                    k = n
                    kt = v
                    onlyup = true
                else
                    kt = T[k]
                    onlyup = false
                end
                while !onlyup
                    i = 2 * k
                    if i > n
                        break
                    end
                    if i == n
                        it = T[i]
                    else
                        lc = T[i]
                        rc = T[i+1]
                        if c[lc] < c[rc]
                            it = lc
                        else
                            it = rc
                            i += 1
                        end
                    end
                    if c[kt] < c[it]
                        break
                    else
                        T[k] = it
                        L[it] = k
                        T[i] = kt
                        L[kt] = i
                        k = i
                    end
                end
                j = k
                tj = T[k]
                while j > 1
                    j2 = round(Int64,floor(j/2))
                    tj2 = T[j2]
                    if c[tj2] < c[tj]
                        break
                    else
                        T[j2] = tj
                        L[tj] = j2
                        T[j] = tj2
                        L[tj2] = j
                        j = j2
                    end
                end
            end
        end
    end
    t_ind = t[ind]
    v = t_ind
    u = p[v]
    d = 0.0
    while !iszero(u)
        d += DIST[u,v]
        v = u
        u = p[v]
    end
    return ind, Route(c[t_ind] / 60.0, d * ENERGY_PER_DISTANCE, [s,t_ind])
end

function dijkstra_taxi_to_nearby_rank(net::Network, s::Int64, t::Vector{Int64}, f::Vector{Float64})
    @unpack DIST, TIME, TIME_REV = net
    @unpack m, colptr, rowval, nzval = TIME_REV
    c = ones(Float64, m) * Inf
    p = zeros(Int64, m)
    T = zeros(Int64, m)
    L = zeros(Int64, m)
    c[s] = 0
    T[1] = s
    L[s] = 1
    n = 1
    inds = zeros(Int64, NUM_NEARBY_RANKS)
    count = 0
    while n > 0
        u = T[1]
        ind = findfirst(t .== u)
        if !isnothing(ind)
            count += 1
            inds[count] = ind
            if count == NUM_NEARBY_RANKS
                break
            end
        end
        n_top = T[n]
        T[1] = n_top
        L[n_top] = 1
        n -= 1
        k = 1
        kt = n_top
        while true
            i = 2 * k
            if i > n
                break
            end
            if i == n
                it = T[i]
            else
                lc = T[i]
                rc = T[i+1]
                if c[lc] < c[rc]
                    it = lc
                else
                    it = rc
                    i += 1
                end
            end
            if c[kt] < c[it]
                break
            else
                T[k] = it
                L[it] = k
                T[i] = kt
                L[kt] = i
                k = i
            end
        end
        for ei = colptr[u]:(colptr[u + 1] - 1)
            v = rowval[ei]
            x = c[u] + nzval[ei]
            if c[v] > x
                c[v] = x
                p[v] = u
                k = L[v]
                if k == 0
                    n += 1
                    T[n] = v
                    L[v] = n
                    k = n
                    kt = v
                    onlyup = true
                else
                    kt = T[k]
                    onlyup = false
                end
                while !onlyup
                    i = 2 * k
                    if i > n
                        break
                    end
                    if i == n
                        it = T[i]
                    else
                        lc = T[i]
                        rc = T[i+1]
                        if c[lc] < c[rc]
                            it = lc
                        else
                            it = rc
                            i += 1
                        end
                    end
                    if c[kt] < c[it]
                        break
                    else
                        T[k] = it
                        L[it] = k
                        T[i] = kt
                        L[kt] = i
                        k = i
                    end
                end
                j = k
                tj = T[k]
                while j > 1
                    j2 = round(Int64,floor(j/2))
                    tj2 = T[j2]
                    if c[tj2] < c[tj]
                        break
                    else
                        T[j2] = tj
                        L[tj] = j2
                        T[j] = tj2
                        L[tj2] = j
                        j = j2
                    end
                end
            end
        end
    end
    ind = inds[argmax(-c[t[inds]] ./ sum(c[t[inds]]) + f[inds])]
    v = t[ind]
    u = p[v]
    m = Vector{Float64}()
    d = Vector{Float64}()
    r = [v]
    while !iszero(u)
        pushfirst!(m, TIME[u,v])
        pushfirst!(d, DIST[u,v])
        pushfirst!(r, u)
        v = u
        u = p[v]
    end
    return ind, Route(m ./ 60.0, d .* ENERGY_PER_DISTANCE, r)
end
