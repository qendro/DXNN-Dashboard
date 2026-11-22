%% Configuration file for FX Trading System
%% Centralized configuration for all system parameters
%% Options listed in comments show available alternatives

-module(config).
-compile(export_all).

-define(CONFIG_TAB, dxnn_config).

%% ===================================================================
%% Trading & Account Setup
%% ===================================================================
account_leverage() -> get_val(account_leverage, 50).                     % Options: 1-500 (typical: 10, 50, 100, 200)
account_initial_balance() -> get_val(account_initial_balance, 300).             % Options: any positive number (typical: 100-10000)
account_lot_size() -> get_val(account_lot_size, 10000).                  % Options: 1000, 10000, 100000 (micro, mini, standard lots)
account_margin() -> get_val(account_margin, 0).                        % Options: 0-1.0 (percentage, 0=no margin requirement)
account_spread() -> get_val(account_spread, 0.000150).                 % Options: 0.00001-0.001 (1-100 pips, typical: 0.00015)
account_extinction_threshold() -> get_val(account_extinction_threshold, 1).    % Options: 1-inf (account equity threshold, 1=disabled extinction)
buy_money_fixed() -> get_val(buy_money_fixed, 100).                     % Options: any positive number (fixed trade size)
min_profit_threshold() -> get_val(min_profit_threshold, 0.000150).           % Options: 0.00001-0.01 (minimum profit in pips)
order_size_percentage() -> get_val(order_size_percentage, 0.2).               % Options: 0.01-1.0 (1%-100% of balance per trade)

%% ===================================================================
%% Market Data Windows
%% ===================================================================
primary_currency_pair() -> get_val(primary_currency_pair, 'EURUSD1').         % Options: 'EURUSD1', 'EURUSD1_LIVE', 'EURUSD15', 'EURUSD30', 'EURUSD60'

% Core data window configuration (all values are "bars back from latest data")
gt_start() -> get_val(gt_start, 1000).                           % Options: 1-N (starting row for training data)
gt_end() -> get_val(gt_end, 200).                              % Options: 1 to gt_start-1 (ending row for training)
bench_start() -> get_val(bench_start, 200).                         % Options: 1-N (starting row for benchmark data)
bench_end() -> get_val(bench_end, last).                          % Options: last, or specific number (ending row for benchmark)

%% ===================================================================
%% Sensor Profiles
%% ===================================================================
%% --- Standard Forex Trader ---
pli_resolutions() -> get_val(pli_resolutions, [90, 270]).                    % Options: [5], [10], [20], [5,10], [10,20], [5,10,20], etc. (creates one sensor per value)
pci_horizontal_resolutions() -> get_val(pci_horizontal_resolutions, [30]).         % Options: [10], [20], [50], [10,20], [20,50], etc. (creates one sensor per value)
pci_vertical_resolutions() -> get_val(pci_vertical_resolutions, [20]).           % Options: [10], [15], [20], [10,15], [15,20], etc. (PCI: Cartesian product HRes×VRes)

%% --- 1-Minute Optimized Trader ---
pli_1m_resolutions() -> get_val(pli_1m_resolutions, [5,10,20]).            % Options: [5], [10], [20], [5,10], [10,20], [5,10,20], [3,5,10,20]
pci_1m_horizontal_resolutions() -> get_val(pci_1m_horizontal_resolutions, [20,30]).   % Options: [10], [20], [30], [10,20], [20,30], [10,20,30]
pci_1m_vertical_resolutions() -> get_val(pci_1m_vertical_resolutions, [10,15]).     % Options: [5], [10], [15], [5,10], [10,15], [5,10,15]
internal_sensor_dimensions() -> get_val(internal_sensor_dimensions, 3).            % Options: 1-10 (trading state dimensions: position, profit, time)

%% ===================================================================
%% Evolution Strategy
%% ===================================================================
evaluation_timeout_ms() -> get_val(evaluation_timeout_ms, 600000).               % Options: any positive integer in milliseconds (default: 600000 = 10 minutes)
specie_size_limit() -> get_val(specie_size_limit, 2).                     % Options: 1-100 (max agents per species)
init_specie_size() -> get_val(init_specie_size, 2).                      % Options: 1-50 (initial agents per species)
evaluations_limit() -> get_val(evaluations_limit, 100000000000).                    % Options: 10-100000 (max evaluations per run)
generation_limit() -> get_val(generation_limit, 1).                     % Options: 1-1000 (max generations per run)
survival_percentage() -> get_val(survival_percentage, 0.5).                  % Options: 0.1-0.9 (percentage of agents that survive)
tot_runs() -> get_val(tot_runs, 1).                               % Options: 1-100 (number of benchmark runs)

%% --- Termination Logic Reference ---
%% Generation = evaluations_limit() / (agents_per_generation * tuning_duration())
%% Example: 100000 evaluations / (100 agents * 10 attempts) = 100 generations

population_evo_alg_f() -> get_val(population_evo_alg_f, generational).        % Options: generational, steady_state
population_selection_f() -> get_val(population_selection_f, competition).       % Options: competition, top3
population_fitness_postprocessor_f() -> get_val(population_fitness_postprocessor_f, none). % Options: none, size_proportional
tot_topological_mutations_functions() -> get_val(tot_topological_mutations_functions, [{ncount_exponential,2}, {ncount_linear,7}]). % Options: {ncount_exponential,0.5}, {ncount_linear,1}

%% ===================================================================
%% Substrate-Specific Configuration
%% ===================================================================
substrate_plasticities() -> get_val(substrate_plasticities, [none, modular_none, hebbian, ojas]).            %Options: none, iterative, abcn, modular_none, hebbian, ojas (iterative - high CPU / Memory usage)
substrate_linkforms() -> get_val(substrate_linkforms, [l2l_feedforward, jordan_recurrent, neuronself_recurrent]).    % Options: l2l_feedforward, fully_interconnected, jordan_recurrent, neuronself_recurrent (l2l_feedforward - best general-purpose choice, fast and stable)

%% ===================================================================
%% NEAT Neuron Configuration (Applies to neurons if fully_interconnected is used in both Neural and Substrate encoding)
%% ===================================================================

morphology() -> get_val(morphology, forex_trader).                  % Options: forex_trader, forex_trader_1m
connection_architecture() -> get_val(connection_architecture, recurrent).        % Options: feedforward, recurrent
agent_encoding_types() -> get_val(agent_encoding_types, [neural]).         % Options: neural, substrate
tuning_duration() -> get_val(tuning_duration, {const,10}).               % Options: {const,N}, {wsize_proportional,N}, {nsize_proportional,N}
tuning_selection_functions() -> get_val(tuning_selection_functions, [dynamic, dynamic_random, active, active_random, current, current_random, all, all_random]). % Note: lastgen/lastgen_random not implemented
annealing_parameters() -> get_val(annealing_parameters, [0.1, 0.5, 1]).                 % Options: [0.1], [0.5], [1], [0.5,1], [0.1,0.5,1]
perturbation_ranges() -> get_val(perturbation_ranges, [0.1, 0.5, 1, 2]).                  % Options: [0.1], [0.5], [1], [2], [0.5,1], [1,2]
heredity_types() -> get_val(heredity_types, [darwinian, lamarckian]).               % Options: darwinian, lamarckian

neural_activation_functions() -> get_val(neural_activation_functions, [tanh, sin, cos, gaussian, absolute, sgn, log, sqrt, linear]). % Note: quadratic, sigmoid, sigmoid1, multiquadric, bin, trinary are implemented but cause crashes (not tracked in AF_Distribution)
neural_plasticity_functions() -> get_val(neural_plasticity_functions, [none, hebbian, hebbian_w, ojas, ojas_w, self_modulationV1, self_modulationV2, self_modulationV3, self_modulationV4, self_modulationV5, self_modulationV6, neuromodulation]). 
neural_aggregation_functions() -> get_val(neural_aggregation_functions, [dot_product, mult_product, diff_product]). % Options: dot_product, mult_product, diff_product

%% --- Mutation Operators ---
%% Format: {OperatorName, Weight} - Weight determines relative probability of selection
%% Available: mutate_weights, mutate_af, mutate_pf, mutate_aggrf, mutate_plasticity_parameters,
%% add_bias, remove_bias, add_neuron, add_inlink, add_outlink, outsplice, add_sensor, add_actuator,
%% add_sensorlink, add_actuatorlink, add_cpp, add_cep
mutation_operators() -> get_val(mutation_operators, [
    %% Weight & Bias Adaptation
    {mutate_weights,25},
    {mutate_af,25},
    {mutate_pf,25},
    {mutate_aggrf,25},
    {mutate_plasticity_parameters,25}, 
    {add_bias,25},
    {remove_bias,10},

    %% Topology Growth
    {add_neuron,95},
    {add_inlink,50},
    {add_outlink,40},
    {outsplice,15},

    %% Sensor & Actuator Expansion
    {add_sensor,15},
    {add_actuator,1},
    {add_sensorlink,30},
    {add_actuatorlink,20},

    %% CPP / CEP Extensions (for HyperNEAT substrate encoding)
    {add_cpp,30},
    {add_cep,30}
]).

%% ===================================================================
%% Fitness Function Selection
%% ===================================================================
fitness_function() -> get_val(fitness_function, curriculum_risk_penalty).                % Options: time_weighted, total_profit, sharpe_ratio, profit_factor, total_return, sortino_ratio, calmar_ratio, curriculum_risk_penalty, phase0_close_trades, phase1_profit_risk, curriculum_trade_quality_profit, phase2_profit_optimization

%% ===================================================================
%% Time-Weighted Fitness Configuration
%% ===================================================================
fitness_discount_rate() -> get_val(fitness_discount_rate, 0.000025).          % Discount rate per cycle for profits (0.000025 = 0.0025%)
fitness_loss_discount_rate() -> get_val(fitness_loss_discount_rate, 0.000025).     % Discount rate per cycle for losses (additive, 0.000025 = 0.0025%)
fitness_realized_bonus() -> get_val(fitness_realized_bonus, 1.50).             % Bonus multiplier for realized profits (1.50 = 50% bonus, encourages closing profitable trades)
fitness_loss_penalty() -> get_val(fitness_loss_penalty, 1.3).                % Penalty multiplier for realized losses (1.3 = 30% penalty, reduced to encourage closing losing trades)
fitness_unrealized_penalty() -> get_val(fitness_unrealized_penalty, 0.4).         % Penalty multiplier for unrealized PL (0.4 = 40% of value, strongly encourages realization)
fitness_trades_bonus() -> get_val(fitness_trades_bonus, 100).                 % Flat bonus added to fitness if any trades were made (encourages trading activity)
fitness_time_weighted_enabled() -> get_val(fitness_time_weighted_enabled, true).      % Enable/disable time-weighted fitness (true/false)

%% ===================================================================
%% Curriculum Risk Penalty Fitness Configuration
%% ===================================================================
fitness_curriculum_generation() -> get_val(fitness_curriculum_generation, 0).         % Current generation index (for curriculum learning, default: 0)
fitness_curriculum_unrealized_discount() -> get_val(fitness_curriculum_unrealized_discount, 0.3).  % k: Unrealized PnL discount factor (default: 0.3)
fitness_curriculum_pnl_scale() -> get_val(fitness_curriculum_pnl_scale, 100.0).       % S_P: P&L scale per 1000 steps (default: 100.0)
fitness_curriculum_trades_per_1000() -> get_val(fitness_curriculum_trades_per_1000, 3.0).  % Desired trades per 1000 steps (default: 20.0)
fitness_curriculum_generation_focus() -> get_val(fitness_curriculum_generation_focus, 50).  % G_trade_focus: Generation where profit dominates (default: 50)
fitness_curriculum_drawdown_floor() -> get_val(fitness_curriculum_drawdown_floor, 0.10).    % DD_floor: Drawdown tolerated (default: 0.10 = 10%)
fitness_curriculum_drawdown_penalty() -> get_val(fitness_curriculum_drawdown_penalty, 3.0). % lam: Drawdown penalty strength (default: 3.0)

%% ===================================================================
%% Phase 1 Profit Risk Fitness Configuration
%% ===================================================================
fitness_phase1_pscore_weight() -> get_val(fitness_phase1_pscore_weight, 0.40).      % Weight for PnL score in phase1_profit_risk (default: 0.40)
fitness_phase1_tradescore_weight() -> get_val(fitness_phase1_tradescore_weight, 0.60).  % Weight for trade score in phase1_profit_risk (default: 0.60)

%% ===================================================================
%% Curriculum Trade Quality Profit Fitness Configuration
%% ===================================================================
fitness_target_trades_per_1000() -> get_val(fitness_target_trades_per_1000, 50.0).  % Target trades per 1000 timesteps (default: 50.0)
fitness_overtrade_thresh_per_1000() -> get_val(fitness_overtrade_thresh_per_1000, 150.0).  % Overtrade threshold per 1000 timesteps (default: 150.0)
fitness_overtrade_lambda() -> get_val(fitness_overtrade_lambda, 0.08).  % Overtrade penalty decay rate (default: 0.08)
fitness_curriculum_g1() -> get_val(fitness_curriculum_g1, 15).  % Generation milestone 1 for curriculum schedule (default: 15)
fitness_curriculum_g2() -> get_val(fitness_curriculum_g2, 60).  % Generation milestone 2 for curriculum schedule (default: 60)
fitness_no_trade_penalty() -> get_val(fitness_no_trade_penalty, 0.5).  % Penalty for no trades in trade score (default: 0.5)
fitness_dom_scale() -> get_val(fitness_dom_scale, 10.0).  % Scale for dominance score calculation (default: 10.0)
fitness_bigwin_pct() -> get_val(fitness_bigwin_pct, 0.005).  % Big win threshold as percentage of starting balance (default: 0.005 = 0.5%)
fitness_bigwin_sum_scale() -> get_val(fitness_bigwin_sum_scale, 1.0).  % Scale for big win sum normalization (default: 1.0)
fitness_target_bigwins_per_1000() -> get_val(fitness_target_bigwins_per_1000, 5.0).  % Target big wins per 1000 timesteps (default: 5.0)
fitness_unreal_discount_no_trades() -> get_val(fitness_unreal_discount_no_trades, 0.1).  % Unrealized discount when no trades (default: 0.1)
fitness_dd_lambda_early() -> get_val(fitness_dd_lambda_early, 1.0).  % Early generation drawdown penalty strength (default: 1.0)
fitness_dd_lambda_late() -> get_val(fitness_dd_lambda_late, 4.0).  % Late generation drawdown penalty strength (default: 4.0)
%% Note: fitness_curriculum_drawdown_floor, fitness_curriculum_pnl_scale, and fitness_curriculum_unrealized_discount
%% are already defined in the "Curriculum Risk Penalty Fitness Configuration" section above

%% ===================================================================
%% Checkpoint Configuration
%% ===================================================================
checkpoint_enabled() -> get_val(checkpoint_enabled, auto).              % Options: auto, true, false (auto = detect AWS environment)

%% ===================================================================
%% Population Configuration
%% ===================================================================
population_id() -> get_val(population_id, test).                        % Options: test, or any atom/string identifier for the population

%% ===================================================================
%% System & Diagnostics
%% ===================================================================
fx_tables_directory() -> get_val(fx_tables_directory, "fx_tables/").         % Options: any valid directory path
source_directory() -> get_val(source_directory, "fx_tables/").            % Options: any valid directory path
actuator_debug_tag() -> get_val(actuator_debug_tag, false).                 % Options: true, false (enables trade-by-trade debug output)
sensor_debug_tag() -> get_val(sensor_debug_tag, false).                   % Options: true, false (enables sensor debug output)

%% ===================================================================
%% Dynamic Configuration Override System (ETS-based)
%% ===================================================================
init() ->
	case ets:info(?CONFIG_TAB) of
		undefined -> ets:new(?CONFIG_TAB, [set, public, named_table]), ok;
		_ -> ok
	end.

set(Key, Value) ->
	init(),
	ets:insert(?CONFIG_TAB, {Key, Value}).

get_val(Key, Default) ->
	case ets:info(?CONFIG_TAB) of
		undefined -> Default;
		_ ->
			case ets:lookup(?CONFIG_TAB, Key) of
				[{Key, Value}] -> Value;
				[] -> Default
			end
	end.

clear() ->
	case ets:info(?CONFIG_TAB) of
		undefined -> ok;
		_ -> ets:delete_all_objects(?CONFIG_TAB)
	end.

load_from_list(ConfigList) ->
	init(),
	[set(Key, Value) || {Key, Value} <- ConfigList],
	ok.
