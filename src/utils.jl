"""
    tensor_address(degree::I, adolc_partial::Vector{I}) where I <: Integer
    tensor_address(degree::Cint, adolc_partial::Vector{I}) where I <: Integer
    tensor_address(degree::I, adolc_partial::Vector{Cint}) where I <: Integer
    tensor_address(degree::Cint, adolc_partial::Vector{Cint})

Generates the index (address) of the mixed-partial specified by `adolc_partial`
in an higher-order derivative tensor of derivative order `degree`.

!!! note 
    The partial has to be in [ADOLC-Format](@ref).
"""
function tensor_address(degree::I, adolc_partial::Vector{I}) where I <: Integer
    return tensor_address(Cint(degree), convert(Vector{Cint}, adolc_partial))
end

function tensor_address(degree::Cint, adolc_partial::Vector{I}) where I <: Integer
    return tensor_address(degree, convert(Vector{Cint}, adolc_partial))
end

function tensor_address(degree::I, adolc_partial::Vector{Cint}) where I <: Integer
    return tensor_address(Cint(degree), adolc_partial)
end

function tensor_address(degree::Cint, adolc_partial::Vector{Cint})
    # "+1" because c++ indexing is -1
    return TbadoubleModule.tensor_address(degree, adolc_partial) + 1
end


"""
    partial_to_adolc_format(partial::Vector{I_1}, degree::I_2) where {I_1<:Integer, I_2<:Integer}

Transforms a given partial to the [ADOLC-Format](@ref). 

!!! note

    `partial` is required to be in the `Partial-format`

# Example:
```jldoctest
using ADOLC
partial = [1, 0, 4]
degree = sum(partial)
partial_to_adolc_format(partial, degree)

# output

5-element Vector{Int32}:
 3
 3
 3
 3
 1
```
"""
function partial_to_adolc_format(partial::Vector{I_1}, degree::I_2) where {I_1<:Integer, I_2<:Integer}
    res = Vector{Cint}(undef, degree)
    partial_to_adolc_format!(res, partial, degree)
    return res
end

"""
    partial_to_adolc_format!(res::Vector{Cint}, partial::Vector{I_1}, degree::I_2) where {I_1<:Integer, I_2<:Integer}
    partial_to_adolc_format!(res::Vector{Cint}, partial::Vector{Cint}, degree::I) where I <: Integer

    
Variant of [`partial_to_adolc_format`](@ref) that writes the result to `res`.
    

# Example:
```jldoctest
using ADOLC
partial = [1, 3, 2, 0]
degree = sum(partial)
res = zeros(Int32, degree)
partial_to_adolc_format!(res, partial, degree)

# output

6-element Vector{Int32}:
 3
 3
 2
 2
 2
 1
```
"""
function partial_to_adolc_format!(res::Vector{Cint}, partial::Vector{I_1}, degree::I_2) where {I_1<:Integer, I_2<:Integer}
    partial_to_adolc_format!(res, convert(Vector{Cint}, partial), degree)
end

function partial_to_adolc_format!(res::Vector{Cint}, partial::Vector{Cint}, degree::I) where I <: Integer
    idx = 1
    for i in eachindex(partial)
        for _ in 1:partial[i]
            res[idx] = i
            idx += 1
        end
    end
    for i in idx:degree
        res[i] = 0
    end
    return sort!(res; rev=true)
end

"""
    create_cxx_identity(n::I_1, m::I_2) where {I_1 <: Integer, I_2 <: Integer}

Creates a identity matrix of shape (`n`, `m`) of type CxxPtr{CxxPtr{Float64}} (wrapper of C++'s double**).


# Example
```jldoctest
using ADOLC
id = create_cxx_identity(2, 4)
for i in 1:2
    for j in 1:4
        print(id[i, j], " ")
    end
    println("")
end

# output

1.0 0.0 0.0 0.0 
0.0 1.0 0.0 0.0
```
"""
function create_cxx_identity(n::I_1, m::I_2) where {I_1 <: Integer, I_2 <: Integer}
    I = myalloc2(n, m)
    for i in 1:n
        for j in 1:m
            I[i, j] = 0.0
            if i == j
                I[i, i] = 1.0
            end
        end
    end
    return I
end


"""
    create_partial_cxx_identity(n::I_1, idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}

Creates a matrix of shape (`n`, `length(idxs)`) of type CxxPtr{CxxPtr{Float64}} (wrapper of C++'s double**).
The columns are canonical basis vectors corresponding to the entries of `idxs`. The order of the basis vectors
is defined by the order of the indices in `idxs`.

!!! warning
    The number of rows `n` must be smaller than the maximal index of `idxs`!

!!! warning
    The values of `idxs` must be non-negative!

# Examples
```jldoctest
using ADOLC
n = 4
idxs = [1, 3]
id = create_partial_cxx_identity(n, idxs)
for i in 1:4
    for j in 1:length(idxs)
        print(id[i, j], " ")
    end
    println("")
end

# output

1.0 0.0 
0.0 0.0
0.0 1.0
0.0 0.0
```
The order in `idxs` defines the order of the basis vectors.
```jldoctest
using ADOLC
n = 3
idxs = [3, 0, 1]
id = create_partial_cxx_identity(n, idxs)
for i in 1:3
    for j in 1:length(idxs)
        print(id[i, j], " ")
    end
    println("")
end

# output

0.0 0.0 1.0
0.0 0.0 0.0
1.0 0.0 0.0
```
"""
function create_partial_cxx_identity(n::I_1, idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}
    if n < maximum(idxs)
        throw("ArgumentError: The number of rows must be greater than the largest index: $n < $(maximum(idxs)).")
    end       
    m = length(idxs)
    I = myalloc2(n, m)
    for j in 1:m
        for i in 1:n
            I[i, j] = 0.0
        end
        if idxs[j] > 0
            I[idxs[j], j] = 1.0
        end
    end
    return I
end

"""
    seed_idxs_partial_format(partials::Vector{Vector{I}}) where I <: Integer

Extracts the actually required derivative directions of `partials` and returns them 
ascendet sorted. 

!!! note
    `partials` has to be in [Partial-Format](@ref).

# Example
```jldoctest
using ADOLC

partials = [[1, 0, 0, 0, 3], [1, 0, 1, 0, 0], [0, 0, 3, 0, 0]]
seed_idxs_partial_format(partials)

# output

3-element Vector{Int64}:
 1
 3
 5
```
"""
function seed_idxs_partial_format(partials::Vector{Vector{I}}) where I <: Integer
    seed_idxs = Vector{I}()
    for partial in partials
        for i in eachindex(partial)
            if partial[i] != 0
                if !(i in seed_idxs)
                    push!(seed_idxs, i)
                end
            end
        end
    end
    sort!(seed_idxs)
    return seed_idxs
end

"""
    seed_idxs_adolc_format(partials::Vector{Vector{I}}) where I <: Integer


Extracts the actually required derivative directions of `partials` and returns them 
ascendet sorted. 

!!! note

    `partials` has to be in [ADOLC-Format](@ref).

# Example
```jldoctest
using ADOLC

partials = [[5, 5, 5, 1], [3, 1, 0, 0], [3, 3, 3, 0]]
seed_idxs_adolc_format(partials)

# output

3-element Vector{Int64}:
 1
 3
 5
```
"""
function seed_idxs_adolc_format(partials::Vector{Vector{I}}) where I <: Integer
    seed_idxs = Vector{I}()
    for partial in partials
        for i in partial
            if i != 0
                if !(i in seed_idxs)
                    push!(seed_idxs, i)
                end
            end
        end
    end
    sort!(seed_idxs)
    return seed_idxs
end
"""
    partial_format_to_seed_space(partials::Vector{Vector{I_1}}, seed_idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}
    partial_format_to_seed_space(partials::Vector{Vector{I}}) where I <: Integer

Converts `partials` in [Partial-Format](@ref) to `partials` of the same format but with (possible) reduced number 
of derivatives directions. The `seed_idxs` is expected to store the result of [`seed_idxs_partial_format(seed_idxs)`](@ref).
Without `seed_idxs` the function first calls [`seed_idxs_partial_format(seed_idxs)`](@ref) to get the indices.

# Examples
```jldoctest
using ADOLC

partials = [[0, 1, 1], [0, 2, 0]]
seed_idxs = seed_idxs_partial_format(partials)
partial_format_to_seed_space(partials, seed_idxs)

# output

2-element Vector{Vector{Int64}}:
 [1, 1]
 [2, 0]
```
Without `seed_idxs`
```jldoctest
using ADOLC

partials = [[0, 1, 1], [0, 2, 0]]
partial_format_to_seed_space(partials)

# output

2-element Vector{Vector{Int64}}:
 [1, 1]
 [2, 0]
```
"""
function partial_format_to_seed_space(partials::Vector{Vector{I_1}}, seed_idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}
    seed_space_partials = Vector{Vector{Int64}}(undef, length(partials))
    for (i, partial) in enumerate(partials)
        seed_space_partials[i] = zeros(length(seed_idxs))
        for j in eachindex(partial)
            if partial[j] != 0
                seed_space_partials[i][indexin(j, seed_idxs)[1]] = partial[j]
            end
        end
    end
    return seed_space_partials
end

function partial_format_to_seed_space(partials::Vector{Vector{I}}) where I <: Integer
    seed_idxs = seed_idxs_partial_format(partials)
    return partial_format_to_seed_space(partials, seed_idxs)
end


"""
    adolc_format_to_seed_space(partials::Vector{Vector{I_1}}, seed_idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}
    adolc_format_to_seed_space(partials::Vector{Vector{I}}) where I <: Integer

Same as [`partial_format_to_seed_space`](@ref) but with [ADOLC-Format](@ref).

# Examples
```jldoctest
using ADOLC

partials = [[3, 2], [2, 2]]
seed_idxs = seed_idxs_adolc_format(partials)
adolc_format_to_seed_space(partials, seed_idxs)

# output

2-element Vector{Vector{Int64}}:
 [2, 1]
 [1, 1]
```
Without `seed_idxs`
```jldoctest
using ADOLC

partials = [[3, 2], [2, 2]]
seed_idxs = seed_idxs_adolc_format(partials)
adolc_format_to_seed_space(partials, seed_idxs)

# output

2-element Vector{Vector{Int64}}:
 [2, 1]
 [1, 1]
```
"""
function adolc_format_to_seed_space(
    partials::Vector{Vector{I_1}}, seed_idxs::Vector{I_2}) where {I_1 <: Integer, I_2 <: Integer}
    new_partials = Vector{Vector{Int64}}(undef, length(partials))
    for (i, partial) in enumerate(partials)
        new_partials[i] = zeros(length(partial))
        for j in eachindex(partial)
            if partial[j] != 0
                new_partials[i][j] = indexin(partial[j], seed_idxs)[1]
            else # since adolc_format is sorted, first zero means everything afterward is zero
                break
            end
        end
    end
    return new_partials
end

function adolc_format_to_seed_space(
    partials::Vector{Vector{I}}) where I <: Integer
    seed_idxs = seed_idxs_adolc_format(partials)
    return adolc_format_to_seed_space(partials, seed_idxs)
end

function build_tensor(
    derivative_order::Int64, num_dependents::Int64, num_independents::Int64, CxxTensor
)

    # allocate the output (julia) tensor 
    tensor = Array{Float64}(
        undef, [num_independents for _ in 1:derivative_order]..., num_dependents
    )

    # creates all index-pairs; the i-th entry specifies the i-th directional derivative w.r.t x_i
    # e.g. (1, 1, 3, 4) gives the derivative w.r.t x_1, x_1, x_3, x_4
    # this is used as index for the tensor and to get the address from the compressed vector
    idxs = vec(
        collect(
            Iterators.product(Iterators.repeated(1:num_independents, derivative_order)...)
        ),
    )

    # build the tensor
    for idx in idxs
        for component in 1:num_dependents
            tensor[idx..., component] = CxxTensor[
                component, tensor_address2(derivative_order, idx)
            ]
        end
    end
    return tensor
end
