%%%-------------------------------------------------------------------
%%% File    : web_static.erl
%%% Author  : asceth <machinist@asceth.com>
%%% Description : Server process that handles query requests internally
%%%                and provides the fun for the mochiweb loop.
%%%
%%% Created :  9 Sep 2008 by asceth <machinist@asceth.com>
%%%-------------------------------------------------------------------
-module(web_static).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% External API
-export([setup/0]).
-export([reload_layout/0, reload_pages/0]).
-export([get_option/1]).
-export([loop/3]).

-record(state, {router}).

-include("logger.hrl").

-define(SERVER, ?MODULE).
-define(HTTPSERVER, web_static_httpserver).


%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link(Options) -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Options) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [Options], []).


%%====================================================================
%% External API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: loop(Req, DocRoot) -> void()
%% Description: Loop for the mochiweb http server
%%--------------------------------------------------------------------
loop(WebRouter, Req, _DocRoot) ->
  statistics(wall_clock),
  Path = Req:get(path),
  PathTokens = string:tokens(Path, "/"),
  Method = case Req:get(method) of
             'GET' ->
               get;
             'HEAD' ->
               get;
             'POST' ->
               PostParams = Req:parse_post(),
               case lists:keysearch("_method", 1, PostParams) of
                 {value, {"_method", "put"}} ->
                   put;
                 {value, {"_method", "delete"}} ->
                   delete;
                 _UnknownNone ->
                   post
               end;
             'PUT' ->
               put;
             'DELETE' ->
               delete;
             _Unknown ->
               error
           end,
  case Method of
    error ->
      Req:respond({501, [], []});
    RouteMethod ->
      Response = try do_request(WebRouter, Method, PathTokens, Req)
                 catch
                   throw:{route_error, StatusCode, Data} ->
                     [RouteErrorResponse] = web_router:run(WebRouter, request_error,
                                                           StatusCode, [RouteMethod, PathTokens, Req, Data]),
                     RouteErrorResponse;
                   error:function_clause ->
                     [FunctionClauseResponse] = web_router:run(WebRouter, request_error,
                                                               403, [RouteMethod, PathTokens, Req, []]),
                     FunctionClauseResponse;
                   error:Error ->
                     ?ERROR_MSG("~p~nError: ~p~nTrace: ~p~n~n", [httpd_util:rfc1123_date(erlang:universaltime()), Error, erlang:get_stacktrace()]),
                     [ErrorResponse] = web_router:run(WebRouter, request_error,
                                                      500, [RouteMethod, PathTokens, Req, []]),
                     ErrorResponse
                 end,
      {_, Time1} = statistics(wall_clock),
      U1 = Time1 / 1000,
      ReqsASec = case U1 of
                   0.0 ->
                     0;
                   Other ->
                     1 / Other
                 end,
      ?INFO_MSG("==== SERVING ====~nPath: ~p~nRequest Time: ~p (~p reqs/s)~n",
                [Path, U1, ReqsASec]),
      {status, Status, headers, Headers, body, Body} = Response,
      Req:respond({Status, Headers, Body})
  end.


reload_layout() ->
  gen_server:cast(?SERVER, reload_layout).
reload_pages() ->
  gen_server:cast(?SERVER, reload_pages).

%%--------------------------------------------------------------------
%% Function: get_option(option_name) -> OptionValue | error
%%--------------------------------------------------------------------
get_option(database_pool) ->
  gen_server:call(?SERVER, get_database_pool);
get_option(web_router) ->
  gen_server:call(?SERVER, get_web_router_name);
get_option(_Other) ->
  error.

setup() ->
  application:start(web_pages),
  application:start(web_layout),
  application:start(adv_crypto),
  application:start(inets),
  application:start(mochiweb),
  application:start(web_static).


%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%% WebConfig = [{ip, "127.0.0.1"}, {port, 8000}, {docroot, "/srv/web/gamesyn.com/public"}, {web_router, web_static_router}].
%%--------------------------------------------------------------------
init([Options]) ->
  {DocRoot, Options1} = get_option(docroot, Options),
  {WebRouter, Options2} = get_option(web_router, Options1),

  reload_layout(WebRouter),
  reload_pages(WebRouter),

  {A1, A2, A3} = now(),
  random:seed(A1, A2, A3),
  Loop = fun(Req) ->
             ?SERVER:loop(WebRouter, Req, DocRoot)
         end,
  mochiweb_http:start([{name, ?HTTPSERVER}, {loop, Loop} | Options2]),
  {ok, #state{router=WebRouter}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call(get_web_router_name, _From, #state{router=WebRouter} = State) ->
  {reply, WebRouter, State};
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(reload_layout, #state{router=WebRouter} = State) ->
  reload_layout(WebRouter),
  {noreply, State};
handle_cast(reload_pages, #state{router=WebRouter} = State) ->
  reload_pages(WebRouter),
  {noreply, State};
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, #state{router=_WebRouter} = _State) ->
  mochiweb_http:stop(?SERVER),
  ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

get_option(Option, Options) ->
  {proplists:get_value(Option, Options), proplists:delete(Option, Options)}.

reload_layout(WebRouter) ->
  web_layout:register_layout(default, WebRouter, code:priv_dir(?SERVER) ++ "/layout/static.herml").

reload_pages(WebRouter) ->
  web_pages:load_pages(WebRouter, code:priv_dir(?SERVER) ++ "/pages").


do_request(WebRouter, Method, PathTokens, Req) ->
  Session = hook_pre_request(WebRouter, Method, PathTokens, Req),
  SessionFinal = hook_post_request(WebRouter, Session),
  {status, web_session:flash_lookup(SessionFinal, "status"), headers, web_session:flash_lookup(SessionFinal, "headers"), body, web_session:flash_lookup(SessionFinal, "body")}.

hook_pre_request(WebRouter, Method, PathTokens, Req) ->
  [Session] = web_router:run(WebRouter, pre_request, global,
                             [[{"method", Method}, {"path_tokens", PathTokens}, {"request", Req}]]),

  case web_router:run(WebRouter, pre_request, web_session:flash_lookup(Session, "first_path_token"), [Session]) of
    [{error, Error, session, Session1}] ->
      do_error(WebRouter, pre_request, Error, Session1);
    [{redirect, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", 301}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [{redirect, StatusCode, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", StatusCode}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [{ok, Session1}] ->
      hook_request_global(WebRouter, Session1);
    [] ->
      hook_request_global(WebRouter, Session)
  end.

hook_request_global(WebRouter, Session) ->
  case web_router:run(WebRouter, request, global, [Session]) of
    [] ->
      hook_request_path(WebRouter, Session);
    [{error, Error, session, Session1}] ->
      do_error(WebRouter, request, Error, Session1);
    [{redirect, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", 301}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [{redirect, StatusCode, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", StatusCode}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [Session1] ->
      hook_request_path(WebRouter, Session1)
  end.

hook_request_path(WebRouter, Session) ->
  case web_router:run(WebRouter, request, web_session:flash_lookup(Session, "first_path_token"), [Session]) of
    [] ->
      do_status(WebRouter, request, 403, Session);
    [{error, Error, session, Session1}] ->
      do_error(WebRouter, request, Error, Session1);
    [{redirect, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", 301}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [{redirect, StatusCode, Url, session, Session1}] ->
      web_session:flash_merge_now(Session1, [{"status", StatusCode}, {"headers", [{"Location", Url}]}, {"body", <<>>}]);
    [{session, Session1, view_tokens, ViewTokens}] ->
      Session2 = web_session:flash_merge_now(Session1, [{"view_tokens", ViewTokens}]),
      hook_views(WebRouter, Session2);
    [Session1] ->
      Session2 = web_session:flash_merge_now(Session1, [{"view_tokens", web_session:flash_lookup(Session1, "path_tokens")}]),
      hook_views(WebRouter, Session2)
  end.

hook_views(WebRouter, Session) ->
  ViewTokens = web_session:flash_lookup(Session, "view_tokens"),

  Body0 = web_router:run(WebRouter, pre_request_view, global, [Session]),
  Body1 = web_router:run(WebRouter, pre_request_view, ViewTokens, [Session]),

  Body2 = web_router:run(WebRouter, request_view, global, [Session]),
  Body3 = web_router:run(WebRouter, request_view, ViewTokens, [Session]),

  Body4 = web_router:run(WebRouter, post_request_view, ViewTokens, [Session]),
  Body5 = web_router:run(WebRouter, post_request_view, global, [Session]),

  RenderedBody = [Body0, Body1, Body2, Body3, Body4, Body5],
  Session1 = web_session:flash_merge_now(Session, [{"YieldedContent", RenderedBody}]),
  BodyFinal = case web_router:run(WebRouter, request_layout_view, global, [Session1]) of
                [] ->
                  RenderedBody;
                BodyWithLayout ->
                  BodyWithLayout
              end,
  web_session:flash_merge_now(Session1, [{"body", BodyFinal}]).

hook_post_request(WebRouter, Session) ->
  Session1 = case web_router:run(WebRouter, post_request, global, [Session]) of
               [] ->
                 Session;
               [Response1] ->
                 Response1
             end,
  case web_router:run(WebRouter, post_request, web_session:flash_lookup(Session, "first_path_token"), [Session]) of
    [] ->
      Session1;
    [Response2] ->
      Response2
  end.

do_error(WebRouter, Hook, Error, Session) ->
  ?ERROR_MSG("~p~nRequest: ~p~nHook: ~p~nError: ~p~n~n", [httpd_util:rfc1123_date(erlang:universaltime()),
                                                          web_session:flash_lookup(Session, "request"), Hook, Error]),
  case web_router:run(WebRouter, request_error, 500, [Session, Error]) of
    [] ->
      web_session:flash_merge_now(Session, [{"status", 500}, {"headers", []}, {"body", <<"500">>}]);
    [Response] ->
      {status, Status, headers, Headers, body, Body} = Response,
      web_session:flash_merge_now(Session, [{"status", Status}, {"headers", Headers}, {"body", Body}])
  end.

do_status(WebRouter, Hook, Status, Session) ->
  ?WARNING_MSG("~p~nRequest: ~p~nHook: ~p~nStatus: ~p~n~n", [httpd_util:rfc1123_date(erlang:universaltime()),
                                                             web_session:flash_lookup(Session, "request"), Hook, Status]),
  case web_router:run(WebRouter, request_error, Status, [Session]) of
    [] ->
      web_session:flash_merge_now(Session, [{"status", Status}, {"headers", []}, {"body", list_to_binary(integer_to_list(Status))}]);
    [Response] ->
      {status, Status1, headers, Headers, body, Body} = Response,
      web_session:flash_merge_now(Session, [{"status", Status1}, {"headers", Headers}, {"body", Body}])
  end.

