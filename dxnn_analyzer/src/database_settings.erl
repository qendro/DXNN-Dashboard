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
            [];
        true ->
            discover_databases(FolderStr)
    end.

%% Internal functions

discover_databases(Path) ->
    case classify_database_path(Path) of
        {run_root, _MnesiaPath} ->
            [database_entry(Path)];
        mnesia_dir ->
            [database_entry(Path)];
        none ->
            case file:list_dir(Path) of
                {ok, Entries} ->
                    lists:flatmap(fun(Entry) ->
                        ChildPath = filename:join(Path, Entry),
                        case filelib:is_dir(ChildPath) of
                            true -> discover_databases(ChildPath);
                            false -> []
                        end
                    end, lists:sort(Entries));
                {error, _Reason} ->
                    []
            end
    end.

classify_database_path(Path) ->
    RunMnesiaPath = filename:join(Path, "Mnesia.nonode@nohost"),
    case is_mnesia_directory(RunMnesiaPath) of
        true ->
            {run_root, RunMnesiaPath};
        false ->
            case is_mnesia_directory(Path) of
                true -> mnesia_dir;
                false -> none
            end
    end.

database_entry(Path) ->
    Name = filename:basename(Path),
    #{
        path => list_to_binary(Path),
        name => list_to_binary(Name)
    }.

is_mnesia_directory(Path) ->
    case filelib:is_dir(Path) of
        false ->
            false;
        true ->
            has_mnesia_files(Path)
    end.

has_mnesia_files(Path) ->
    case file:list_dir(Path) of
        {ok, Files} ->
            lists:any(fun is_mnesia_file/1, Files);
        {error, _Reason} ->
            false
    end.

is_mnesia_file(File) ->
    lists:suffix(".DCD", File) orelse
    lists:suffix(".DCL", File) orelse
    lists:suffix(".DAT", File).

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
