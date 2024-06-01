using BenchmarkTools
using ADOLC
using ADOLC.TbadoubleModule
using ADOLC.array_types
using Plots
using ForwardDiff
using ReverseDiff
using Printf


include("benchmark_examples.jl")




function plot(suite::Dict)
    experiments = keys(suite)
    for experiment in experiments
        modes = keys(suite[experiment])
        p = Plots.plot()
        for mode in modes
            if mode != "base_time"
                dims_sorted = sort(collect(keys(suite[experiment][mode])))
                mode_vals = [suite[experiment][mode][key] for key in dims_sorted]
                base_times = [suite[experiment]["base_time"][key] for key in dims_sorted]
                Plots.plot!(p, dims_sorted, mode_vals ./ base_times, label = "$mode")
            end
        end
        Plots.plot!(p, legend = :topleft)
        xlabel!(p, "dimension")
        ylabel!(p, "runtime-ratio")
        Plots.savefig(p, "fwd_vs_rvs_$experiment.pdf")
    end
end


function run_base_time(experiment, dim)
    if experiment === BenchmarkExamples.speelpenning
        x = [(i + 1.0) / (2.0 + i) for i = 1:dim]
        time = @benchmark BenchmarkExamples.speelpenning($x)

    elseif experiment === BenchmarkExamples.lin_solve
        x = [(i + 1.0) / (2.0 + i) for i = 1:dim]
        A = BenchmarkExamples.build_banded_matrix(dim)
        time = @benchmark BenchmarkExamples.lin_solve($A, $x)

    else
        throw("$expriment not implemented!")
    end
    time = median(time.times)
    return time
end

function run_mode(experiment, mode, dim)
    x = [(i + 1.0) / (2.0 + i) for i = 1:dim]
    if mode != "ReverseDiff" &&
       mode != "Forward" &&
       mode != "ForwardDiff" &&
       experiment === BenchmarkExamples.speelpenning
        a = [Adouble{TbAlloc}() for _ in eachindex(x)]
        b = [Adouble{TbAlloc}()]
        y = 0.0
        trace_on(0)
        a << x
        b = BenchmarkExamples.speelpenning(a)
        y = b >> y
        trace_off()

    end
    if mode != "ReverseDiff" &&
       mode != "Forward" &&
       mode != "ForwardDiff" &&
       experiment === BenchmarkExamples.lin_solve
        A = BenchmarkExamples.build_banded_matrix(dim)
        a = [Adouble{TbAlloc}() for _ = 1:dim]
        b = [Adouble{TbAlloc}() for _ = 1:dim]
        y = Vector{Float64}(undef, dim)

        trace_on(0)
        a << x
        b = BenchmarkExamples.lin_solve(A, a)
        y = b >> y
        trace_off()
    end

    if mode == "Forward"
        ADOLC.TladoubleModule.set_num_dir(length(x))
        a = Adouble{TlAlloc}(x, true)
        ADOLC.init_gradient(a)

        if experiment == BenchmarkExamples.speelpenning
            time = @benchmark BenchmarkExamples.speelpenning($a)
        else
            A = BenchmarkExamples.build_banded_matrix(dim)
            time = @benchmark BenchmarkExamples.lin_solve($A, $a)
        end

    elseif mode == "ForwardDiff"
        if experiment == BenchmarkExamples.speelpenning
            time = @benchmark ForwardDiff.gradient(BenchmarkExamples.speelpenning, $x)
        else
            A = BenchmarkExamples.build_banded_matrix(dim)
            time = @benchmark ForwardDiff.jacobian(Base.Fix1(BenchmarkExamples.lin_solve, $A), $x)
        end

    elseif mode == "ReverseDiff"
        if experiment == BenchmarkExamples.speelpenning
            time = @benchmark ReverseDiff.gradient(BenchmarkExamples.speelpenning, $x)
        else
            A = BenchmarkExamples.build_banded_matrix(dim)
            time = @benchmark ReverseDiff.jacobian(Base.Fix1(BenchmarkExamples.lin_solve, $A), $x)
        end
    elseif mode == "Forward_TB"
        m = length(y)
        x_tangent = myalloc2(dim, dim)
        for i = 1:dim
            for j = 1:dim
                x_tangent[i, j] = 0.0
                if i == j
                    x_tangent[i, i] = 1.0
                end
            end
        end
        y_tangent = myalloc2(m, dim)

        time = @benchmark fov_forward(0, $m, $dim, $dim, $x, $x_tangent, $y, $y_tangent)

        myfree2(x_tangent)
        myfree2(y_tangent)

    elseif mode == "Reverse"
        m = length(y)
        weights = myalloc2(m, m)
        for i = 1:m
            for j = 1:m
                weights[i, j] = 0.0
                if i == j
                    weights[i, i] = 1.0
                end
            end
        end
        jacobian = myalloc2(m, dim)
        zos_forward(0, m, dim, 1, x, y)
        time = @benchmark fov_reverse(0, $m, $dim, $m, $weights, $jacobian)
        myfree2(weights)
        myfree2(jacobian)

    else
        throw("$mode is not implemented!")
    end
    time = median(time.times)
    return time
end

function run_benchmark(max_dim, steps)
    suite = Dict()
    #modes = ("Forward", "Reverse", "ForwardDiff", "Forward_TB", "ReverseDiff")
    modes = ("Forward", "Reverse")
    experiments = [BenchmarkExamples.speelpenning, BenchmarkExamples.lin_solve]
    dims = Dict(
        BenchmarkExamples.speelpenning => [1, 100:steps:max_dim...],
        BenchmarkExamples.lin_solve => [1, 100:steps:max_dim...],
    )

    for experiment in experiments
        println("Running $experiment ...")
        suite[experiment] = Dict()
        suite[experiment]["base_time"] =
            Dict(dim => run_base_time(experiment, dim) for dim in dims[experiment])
        for mode in modes
            suite[experiment][mode] = Dict()
            for dim in dims[experiment]
                println(
                    "Running $mode - $(indexin(dim, dims[experiment])[1])/$(length(dims[experiment])) ... ",
                )
                suite[experiment][mode][dim] = run_mode(experiment, mode, dim)
            end
        end
    end
    return suite
end



function compute_slope(suite)
    slope = Dict()
    for experiment in keys(suite)
        slope[experiment] = Dict()
        base_times = suite[experiment]["base_time"]
        for mode in keys(suite[experiment])
            if mode != "base_time"
                dims_sorted = sort(collect(keys(suite[experiment][mode])))
                mode_vals =
                    [suite[experiment][mode][key] ./ base_times[key] for key in dims_sorted]
                dim_diff = dims_sorted[2:end] - dims_sorted[1:end-1]
                mode_val_diff = mode_vals[2:end] - mode_vals[1:end-1]
                diff_quotient = mode_val_diff ./ dim_diff
                slope[experiment][mode] = mean(diff_quotient)
            end
        end
    end
    return slope
end

function print_slope(slope)
    for experiment in keys(slope)
        print("Slopes for $experiment: ")
        for mode in keys(slope[experiment])
            @printf "%s: %.2f   " mode slope[experiment][mode]
        end
        println(" ")
    end
end

function print_table(suite)
    for experiment in keys(suite)
        print_experiment(experiment, suite[experiment])
    end
end

function print_experiment(experiment, suite)
    println("experiment: $experiment")
    base_times = suite["base_time"]
    modes = [mode for mode in keys(suite) if mode != "base_time"]
    print("     |")
    for mode in modes
        print(mode, "   |")
    end
    println("")
    for i in [1, 100:100:1000...]
        print("$i     |")
        for mode in modes
            @printf "    %.2f|" suite[mode][i] ./ base_times[i]
        end
        println("")
    end
end

function run()
    suite = run_benchmark(1000, 100)
    plot(suite)
    slope = compute_slope(suite)
    print_slope(slope)
    #print_table(suite)
end


run()