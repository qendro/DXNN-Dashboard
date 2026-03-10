-module(experiment_settings).
-export([
    init/0,
    get_experiments/0,
    add_experiment/2,
    add_experiment/3,
    update_experiment/2,
    remove_experiment/1
]).

-define(SETTINGS_FILE, "./data/experiments.json").

init() ->
    filelib:ensure_dir(?SETTINGS_FILE),
    case filelib:is_file(?SETTINGS_FILE) of
        true -> ok;
        false ->
            DefaultSettings = #{
                <<"experiments">> => []
            },
            save_settings(DefaultSettings)
    end.

get_experiments() ->
    case load_settings() of
        {ok, Settings} -> 
            maps:get(<<"experiments">>, Settings, []);
        {error, _} -> 
            []
    end.

add_experiment(Name, Path) when is_binary(Name), is_binary(Path) ->
    add_experiment(Name, Path, #{}).

add_experiment(Name, Path, Metadata) when is_binary(Name), is_binary(Path), is_map(Metadata) ->
    Settings = case load_settings() of
        {ok, S} -> S;
        {error, _} -> #{<<"experiments">> => []}
    end,
    
    Experiments = maps:get(<<"experiments">>, Settings, []),
    
    % Check if experiment with this name already exists
    Exists = lists:any(fun(Exp) ->
        maps:get(<<"name">>, Exp, <<>>) =:= Name
    end, Experiments),
    
    case Exists of
        true -> {error, already_exists};
        false ->
            BaseExperiment = #{
                <<"name">> => Name,
                <<"path">> => Path
            },
            NewExperiment = maps:merge(BaseExperiment, sanitize_metadata(Metadata)),
            NewExperiments = [NewExperiment | Experiments],
            NewSettings = #{<<"experiments">> => NewExperiments},
            save_settings(NewSettings)
    end.

update_experiment(Name, Metadata) when is_binary(Name), is_map(Metadata) ->
    case load_settings() of
        {ok, Settings} ->
            Experiments = maps:get(<<"experiments">>, Settings, []),
            CleanMetadata = sanitize_metadata(Metadata),
            Updated = lists:map(fun(Exp) ->
                case maps:get(<<"name">>, Exp, <<>>) of
                    Name ->
                        maps:merge(Exp, CleanMetadata);
                    _ ->
                        Exp
                end
            end, Experiments),
            NewSettings = #{<<"experiments">> => Updated},
            save_settings(NewSettings);
        {error, _} ->
            {error, no_settings}
    end.

remove_experiment(Name) when is_binary(Name) ->
    case load_settings() of
        {ok, Settings} ->
            Experiments = maps:get(<<"experiments">>, Settings, []),
            NewExperiments = lists:filter(fun(Exp) ->
                maps:get(<<"name">>, Exp, <<>>) =/= Name
            end, Experiments),
            NewSettings = #{<<"experiments">> => NewExperiments},
            save_settings(NewSettings);
        {error, _} ->
            {error, no_settings}
    end.

%% Internal functions

load_settings() ->
    case file:read_file(?SETTINGS_FILE) of
        {ok, Binary} ->
            try
                {ok, jsx:decode(Binary, [return_maps])}
            catch
                _:_ -> {error, invalid_json}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

save_settings(Settings) ->
    Json = jsx:encode(Settings),
    filelib:ensure_dir(?SETTINGS_FILE),
    file:write_file(?SETTINGS_FILE, Json).

sanitize_metadata(Metadata) ->
    AllowedKeys = [
        <<"bundle_root">>,
        <<"mnesia_path">>,
        <<"logs_path">>,
        <<"analytics_path">>,
        <<"manifest_path">>,
        <<"success_path">>,
        <<"checkpoint_info_path">>
    ],
    maps:fold(fun(Key, Value, Acc) ->
        case lists:member(Key, AllowedKeys) andalso Value =/= undefined of
            true -> maps:put(Key, Value, Acc);
            false -> Acc
        end
    end, #{}, Metadata).
