-module(s3_settings).
-export([
    init/0,
    get_auto_download_path/0,
    set_auto_download_path/1
]).

-define(SETTINGS_FILE, "./data/s3_settings.json").
-define(DEFAULT_PATH, <<"/app/Documents/DXNN_Main/DXNN-Dashboard/Databases/AWS_v1">>).

init() ->
    filelib:ensure_dir(?SETTINGS_FILE),
    case filelib:is_file(?SETTINGS_FILE) of
        true -> ok;
        false ->
            DefaultSettings = #{
                <<"auto_download_path">> => ?DEFAULT_PATH
            },
            save_settings(DefaultSettings)
    end.

get_auto_download_path() ->
    case load_settings() of
        {ok, Settings} -> 
            maps:get(<<"auto_download_path">>, Settings, ?DEFAULT_PATH);
        {error, _} -> 
            ?DEFAULT_PATH
    end.

set_auto_download_path(Path) when is_binary(Path) ->
    Settings = case load_settings() of
        {ok, S} -> S;
        {error, _} -> #{<<"auto_download_path">> => ?DEFAULT_PATH}
    end,
    
    NewSettings = Settings#{<<"auto_download_path">> => Path},
    save_settings(NewSettings).

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
