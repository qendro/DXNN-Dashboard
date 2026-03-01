-module(database_settings).
-export([
    init/0,
    get_folders/0,
    add_folder/1,
    remove_folder/1,
    set_default/1,
    get_default_folder/0,
    scan_databases/1
]).

-define(SETTINGS_FILE, "./data/settings.json").

init() ->
    filelib:ensure_dir(?SETTINGS_FILE),
    case filelib:is_file(?SETTINGS_FILE) of
        true -> ok;
        false ->
            DefaultSettings = #{
                <<"folders">> => [<<"./data/default">>],
                <<"default_folder">> => <<"./data/default">>
            },
            save_settings(DefaultSettings)
    end.

get_folders() ->
    case load_settings() of
        {ok, Settings} -> 
            maps:get(<<"folders">>, Settings, []);
        {error, _} -> 
            []
    end.

add_folder(Folder) when is_binary(Folder) ->
    Settings = case load_settings() of
        {ok, S} -> S;
        {error, _} -> #{<<"folders">> => [], <<"default_folder">> => <<"./data/default">>}
    end,
    
    Folders = maps:get(<<"folders">>, Settings, []),
    case lists:member(Folder, Folders) of
        true -> {error, already_exists};
        false ->
            NewFolders = [Folder | Folders],
            % Ensure default_folder is set
            DefaultFolder = maps:get(<<"default_folder">>, Settings, <<"./data/default">>),
            NewSettings = #{<<"folders">> => NewFolders, <<"default_folder">> => DefaultFolder},
            save_settings(NewSettings)
    end.

remove_folder(Folder) when is_binary(Folder) ->
    case load_settings() of
        {ok, Settings} ->
            Folders = maps:get(<<"folders">>, Settings, []),
            NewFolders = lists:delete(Folder, Folders),
            NewSettings = Settings#{<<"folders">> => NewFolders},
            save_settings(NewSettings);
        {error, _} ->
            {error, no_settings}
    end.

set_default(Folder) when is_binary(Folder) ->
    case load_settings() of
        {ok, Settings} ->
            NewSettings = Settings#{<<"default_folder">> => Folder},
            save_settings(NewSettings);
        {error, _} ->
            {error, no_settings}
    end.

get_default_folder() ->
    case load_settings() of
        {ok, Settings} -> 
            {ok, maps:get(<<"default_folder">>, Settings, <<"./data/default">>)};
        {error, _} -> 
            {ok, <<"./data/default">>}
    end.

scan_databases(Folder) when is_binary(Folder) ->
    FolderStr = binary_to_list(Folder),
    case filelib:is_dir(FolderStr) of
        false -> 
            io:format("Folder does not exist: ~s~n", [FolderStr]),
            [];
        true ->
            % Check if this folder itself is a Mnesia database directory
            % A Mnesia database directory contains .DCD, .DCL, or .DAT files
            IsMnesiaDir = case file:list_dir(FolderStr) of
                {ok, Files} ->
                    lists:any(fun(F) -> 
                        lists:suffix(".DCD", F) orelse 
                        lists:suffix(".DCL", F) orelse 
                        lists:suffix(".DAT", F)
                    end, Files);
                _ -> false
            end,
            
            case IsMnesiaDir of
                true ->
                    % This folder itself is a Mnesia database
                    Name = list_to_binary(filename:basename(FolderStr)),
                    io:format("Found Mnesia database at: ~s (name: ~s)~n", [FolderStr, Name]),
                    [#{path => list_to_binary(FolderStr), name => Name}];
                false ->
                    % Scan subdirectories for Mnesia databases
                    case file:list_dir(FolderStr) of
                        {ok, Entries} ->
                            io:format("Scanning subdirectories in: ~s~n", [FolderStr]),
                            lists:filtermap(fun(Entry) ->
                                EntryPath = filename:join(FolderStr, Entry),
                                case filelib:is_dir(EntryPath) of
                                    true ->
                                        % Check if this subdirectory is a Mnesia database
                                        case file:list_dir(EntryPath) of
                                            {ok, SubFiles} ->
                                                HasMnesiaFiles = lists:any(fun(F) -> 
                                                    lists:suffix(".DCD", F) orelse 
                                                    lists:suffix(".DCL", F) orelse 
                                                    lists:suffix(".DAT", F)
                                                end, SubFiles),
                                                case HasMnesiaFiles of
                                                    true ->
                                                        io:format("Found Mnesia database at: ~s~n", [EntryPath]),
                                                        {true, #{path => list_to_binary(EntryPath), name => list_to_binary(Entry)}};
                                                    false ->
                                                        false
                                                end;
                                            _ -> false
                                        end;
                                    false -> false
                                end
                            end, Entries);
                        {error, Reason} -> 
                            io:format("Error listing directory ~s: ~p~n", [FolderStr, Reason]),
                            []
                    end
            end
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
