module ADOLC
include("array_types.jl")
include("TbadoubleModule.jl")
include("TladoubleModule.jl")



using .array_types
using .TbadoubleModule
using .TladoubleModule


TbAlloc = TbadoubleModule.TbadoubleCxxAllocated
TlAlloc = TladoubleModule.TladoubleCxxAllocated

include("Adouble.jl")
export TbAlloc, TlAlloc, Adouble, getValue, get_gradient


include("arithmetics.jl")

function abs_normal_finalizer(problem)
    finalize(problem.x)
    finalize(problem.y)
    finalize(problem.z)

    finalize(problem.cz)
    finalize(problem.cy)

    finalize(problem.Y)
    finalize(problem.J)
    finalize(problem.Z)
    finalize(problem.L)

end
mutable struct AbsNormalForm

    tape_id::Int64

    m::Int64
    n::Int64
    num_switches::Int32

    x::CxxVector{Float64}
    y::CxxVector{Float64}
    z::CxxVector{Float64}

    cz::CxxVector{Float64}
    cy::CxxVector{Float64}

    Y::CxxMatrix{Float64}
    J::CxxMatrix{Float64}
    Z::CxxMatrix{Float64}
    L::CxxMatrix{Float64}


    function AbsNormalForm(
        tape_id::Int64,
        m::Int64,
        n::Int64,
        x::Vector{Float64},
        y::Vector{Float64},
    )

        num_switches = TbadoubleModule.get_num_switches(tape_id)
        z = CxxVector{Float64}(num_switches)

        cz = CxxVector{Float64}(num_switches)
        cy = CxxVector{Float64}(length(y))

        Y = CxxMatrix{Float64}(length(y), length(x))
        J = CxxMatrix{Float64}(length(y), num_switches)
        Z = CxxMatrix{Float64}(num_switches, length(x))
        L = CxxMatrix{Float64}(num_switches, num_switches)

        problem = new(
            tape_id,
            m,
            n,
            num_switches,
            CxxVector{Float64}(x),
            CxxVector{Float64}(y),
            z,
            cz,
            cy,
            Y,
            J,
            Z,
            L,
        )
        finalizer(abs_normal_finalizer, problem)
    end
    AbsNormalForm() = new()
end

function abs_normal!(abs_normal_form::AbsNormalForm)
    _abs_normal!(
        abs_normal_form.tape_id,
        abs_normal_form.z,
        abs_normal_form.cz,
        abs_normal_form.cy,
        abs_normal_form.Y,
        abs_normal_form.J,
        abs_normal_form.Z,
        abs_normal_form.L,
        abs_normal_form.m,
        abs_normal_form.n,
        abs_normal_form.num_switches,
        abs_normal_form.x,
        abs_normal_form.y,
    )
end

function _abs_normal!(
    tape_id::Int64,
    z_cxx::CxxVector{Float64},
    cz_cxx::CxxVector{Float64},
    cy_cxx::CxxVector{Float64},
    Y_cxx::CxxMatrix{Float64},
    J_cxx::CxxMatrix{Float64},
    Z_cxx::CxxMatrix{Float64},
    L_cxx::CxxMatrix{Float64},
    m::Int64,
    n::Int64,
    num_switches::Int32,
    x_cxx::CxxVector{Float64},
    y_cxx::CxxVector{Float64},
)

    # use c++ double*
    cz = cz_cxx.data
    cy = cy_cxx.data
    x = x_cxx.data
    y = y_cxx.data
    z = z_cxx.data

    # use the c++ double**
    Y = Y_cxx.data
    J = J_cxx.data
    Z = Z_cxx.data
    L = L_cxx.data

    TbadoubleModule.abs_normal(tape_id, m, n, num_switches, x, y, z, cz, cy, Y, J, Z, L)
end


function abs_normal!(
    tape_id::Int64,
    cz::Vector{Float64},
    cy::Vector{Float64},
    Y::Matrix{Float64},
    J::Matrix{Float64},
    Z::Matrix{Float64},
    L::Matrix{Float64},
    m::Int64,
    n::Int64,
    num_switches::Int64,
    x::Vector{Float64},
    y::Vector{Float64},
    z::Vector{Float64},
)

    # julia matrix to c++ matrix
    Y_cxx = CxxMatrix(Y)
    J_cxx = CxxMatrix(J)
    Z_cxx = CxxMatrix(Z)
    L_cxx = CxxMatrix(L)

    abs_normal!(tape_id, cz, cy, Y_cxx, J_cxx, Z_cxx, L_cxx, m, n, num_switches, x, y, z)
end

function tensor_address(degree::Int64, adolc_partial::Vector{Int32})
    # "+1" because c++ indexing is -1
    return Int64(TbadoubleModule.tensor_address(degree, adolc_partial)) + 1
end

function partial_to_adolc_scheme!(res::Vector{Int32}, partial::Vector{Int64}, degree::Int64)
    idx = 1
    for i in eachindex(partial)
        for _ = 1:partial[i]
            res[idx] = i
            idx += 1
        end
    end
    for i in idx:degree
        res[i] = 0
    end
    sort!(res, rev = true)
end

function create_cxx_identity(n::Int64, m::Int64)
    I = myalloc2(n, m)
    for i = 1:n
        for j = 1:m
            I[i, j] = 0.0
            if i == j
                I[i, i] = 1.0
            end
        end
    end
    return I
end

function create_partial_cxx_identity(n::Int64, m::Int64, idxs::Vector{Int64})
    I = myalloc2(n, m)
    for i = 1:n
        for j = 1:m
            I[i, j] = 0.0
        end
    end
    for i in idxs
        I[i, i] = 1.0
    end
    return I
end

function get_seed_idxs(partials::Vector{Vector{Int64}})
    seed_idxs = Vector{Int64}()
    for partial in partials
        for i in eachindex(partial)
            if partial[i] != 0
                if !(i in seed_idxs)
                    push!(seed_idxs, i)
                end
            end
        end
    end
    return seed_idxs
end

function get_seed_idxs_adolc_scheme(partials::Vector{Vector{Int64}})
    seed_idxs = Vector{Int64}()
    for partial in partials
        for i in partial
            if i != 0
                if !(i in seed_idxs)
                    push!(seed_idxs, i)
                end
            end
        end
    end
    return seed_idxs
end

function build_tensor(
    derivative_order::Int64,
    num_dependents::Int64,
    num_independents::Int64,
    CxxTensor,
)

    # allocate the output (julia) tensor 
    tensor = Array{Float64}(
        undef,
        [num_independents for _ = 1:derivative_order]...,
        num_dependents,
    )


    # creates all index-pairs; the i-th entry specifies the i-th directional derivative w.r.t x_i
    # e.g. (1, 1, 3, 4) gives the derivative w.r.t x_1, x_1, x_3, x_4
    # this is used as index for the tensor and to get the address from the compressed vector
    idxs = vec(
        collect(
            Iterators.product(Iterators.repeated(1:num_independents, derivative_order)...),
        ),
    )

    # build the tensor
    for idx in idxs
        for component = 1:num_dependents
            tensor[idx..., component] =
                CxxTensor[component, tensor_address2(derivative_order, idx)]
        end
    end
    return tensor
end




function check_input_taylor_coeff(
    num_independents,
    derivative_order::Int64;
    num_directions = nothing,
    init_series = nothing,
)
    if num_directions == 1
        if derivative_order == 1
            @assert(
                init_series !== nothing,
                "For derivative_order=$(derivative_order) and 
                num_directions=$(num_directions) you have to provide an 
                init_series (as a vector) to initialize the taylor series 
                propagation!"
            )

            @assert(
                length(size(init_series)) == 1,
                "Please provide the init_series with length(size(init_series))=1
                and not $(length(size(init_series)))."
            )

            @assert(
                size(init_series)[1] == num_independents,
                "Please provide a init_series of length 
                $(num_independents) to initialize the taylor series 
                propagation. Each entry corresponds to one independant."
            )

        else
            if init_series !== nothing
                @assert(
                    length(size(init_series)) == 2,
                    "Please provide the init_series with length(size(init_series))==2
                    and not $(length(size(init_series)))."
                )
                @assert size(
                    init_series == (num_independents, derivative_order),
                    "The init_series has the wrong shape: $(size(init_series)) but must be
                    ($(num_independents), $(derivative_order)). Please provide the taylor 
                    coefficients of the init_series up to order derivative_order-1. 
                    In detail init_series must have the shape (num_independents, derivative_order)
                    and the i-th column corresponds to the i-1-th taylor coefficient 
                    of the init_series.",
                )
            end
        end
    end
    @assert(
        init_series !== nothing,
        "For derivative_order=$(derivative_order) you have to provide 
        an init_series (as a vector) to initialize the taylor series 
        propagation!"
    )
    @assert(
        length(size(init_series)) == derivative_order,
        "The input for init_series has the wrong shape! Please provide
        a vector of $(num_independents) to initialize the taylor
        series propagation. Each entry corresponds to one independant"
    )
end


function taylor_coeff(
    func,
    init_point,
    num_dependents,
    num_independents,
    derivative_order;
    num_directions = nothing,
    init_series = nothing,
)


    a = [Adouble{TbAlloc}() for _ in eachindex(init_point)]
    y0 = Vector{Float64}(undef, num_dependents)
    tape_num = 1
    keep = 0
    trace_on(tape_num, keep)
    a << init_point
    b = func(a)
    b >> y0
    trace_off(0)

    """
    check_input_taylor_coeff(num_independents, 
                            derivative_order,
                            num_directions=num_directions,
                            init_series=init_series)
    """

    if num_directions === nothing
        num_directions = num_independents

    elseif num_directions == 1
        if derivative_order == 1
            y1 = Vector{Float64}(undef, 2)
            fos_forward(
                tape_num,
                num_dependents,
                num_independents,
                keep,
                init_point,
                init_series,
                y0,
                y1,
            )
            return y0, y1
        else
            Y = myalloc2(num_dependents, derivative_order)
            hos_forward(
                tape_num,
                num_dependents,
                num_independents,
                derivative_order,
                0,
                init_point,
                init_series,
                y0,
                Y,
            )
            return y0, Y
        end
    else
        if derivative_order == 1
            if init_series === nothing
                init_series = myalloc2(num_independents, num_directions)
                for i = 1:num_independents
                    for j = 1:num_directions
                        init_series[i, j] = 0.0
                        if i == j
                            init_series[i, i] = 1.0
                        end
                    end
                end
            end
            Y = myalloc2(num_dependents, num_directions)
            fov_forward(
                tape_num,
                num_dependents,
                num_independents,
                num_directions,
                init_point,
                init_series,
                y0,
                Y,
            )
            return y0, Y
        else
            if init_series === nothing
                init_series = myalloc3(num_independents, num_directions, derivative_order)
                for i = 1:num_independents
                    for j = 1:derivative_order
                        for k = 1:num_directions
                            init_series[i, j, k] = 0.0
                        end
                    end
                end
                for k = 1:num_directions
                    init_series[k, k, 1] = 1.0
                end
            end
            Y = myalloc3(num_dependents, num_directions, derivative_order)
            hov_forward(
                tape_num,
                num_dependents,
                num_independents,
                derivative_order,
                num_independents,
                init_point,
                init_series,
                y0,
                Y,
            )
            return y0, Y
        end
    end
end

include("derivative.jl")
export derivative!

export abs_normal!, AbsNormalProblem, gradient, _gradient_tape_based, _gradient_tape_less
export _higher_order, tensor_address2, build_tensor, create_cxx_identity
export taylor_coeff, check_input_taylor_coeff
export erf, eps

end # module ADOLC
