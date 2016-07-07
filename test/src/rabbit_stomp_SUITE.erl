%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_stomp_SUITE).
-include_lib("common_test/include/ct.hrl").
-compile(export_all).
-import(rabbit_misc, [pget/2]).
-include_lib("amqp_client/include/amqp_client.hrl").
-include("rabbit_stomp_frame.hrl").
-define(DESTINATION, "/queue/bulk-test").
-define(GARBAGE, <<"bdaf63dda9d78b075c748b740e7c3510ad203b07\nbdaf63dd">>).

all() ->
    [
     test_messages_not_dropped_on_disconnect,
     test_direct_client_connections_are_not_leaked
    ].

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:merge_app_env(
                Config,
                {rabbitmq_stomp, [{default_user,     []},
                                  {ssl_cert_login,   true}]}),
    rabbit_ct_helpers:run_setup_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

count_connections(Config) ->
    IPv4Count = try
        %% Count IPv4 connections. On some platforms, the IPv6 listener
        %% implicitely listens to IPv4 connections too so the IPv4
        %% listener doesn't exist. Thus this try/catch. This is the case
        %% with Linux where net.ipv6.bindv6only is disabled (default in
        %% most cases).
        rabbit_ct_broker_helpers:rpc(Config, 0, ranch_server, count_connections,
                                     [{acceptor, {0,0,0,0}, stomp_port(Config)}])
    catch
        _:{badarg, _} -> 0
    end,
    IPv6Count = try
        %% Count IPv6 connections. We also use a try/catch block in case
        %% the host is not configured for IPv6.
        rabbit_ct_broker_helpers:rpc(Config, 0, ranch_server, count_connections,
                                     [{acceptor, {0,0,0,0,0,0,0,0}, stomp_port(Config)}])
    catch
        _:{badarg, _} -> 0
    end,
    IPv4Count + IPv6Count.

stomp_port(Config) ->
    rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_stomp).

hostname(Config) ->
    ?config(rmq_hostname, Config).

test_direct_client_connections_are_not_leaked(Config) ->
    N = count_connections(Config),
    lists:foreach(fun (_) ->
                          {ok, Client = {Socket, _}} = rabbit_stomp_client:connect(hostname(Config), stomp_port(Config)),
                          %% send garbage which trips up the parser
                          gen_tcp:send(Socket, ?GARBAGE),
                          rabbit_stomp_client:send(
                           Client, "LOL", [{"", ""}])
                  end,
                  lists:seq(1, 100)),
    timer:sleep(5000),
    N = count_connections(Config),
    ok.

test_messages_not_dropped_on_disconnect(Config) ->
    N = count_connections(Config),
    {ok, Client} = rabbit_stomp_client:connect(hostname(Config), stomp_port(Config)),
    N1 = N + 1,
    N1 = count_connections(Config),
    [rabbit_stomp_client:send(
       Client, "SEND", [{"destination", ?DESTINATION}],
       [integer_to_list(Count)]) || Count <- lists:seq(1, 1000)],
    rabbit_stomp_client:disconnect(Client),
    QName = rabbit_misc:r(<<"/">>, queue, <<"bulk-test">>),
    timer:sleep(3000),
    N = count_connections(Config),
    rabbit_amqqueue:with(
      QName, fun(Q) ->
                     1000 = pget(messages, rabbit_amqqueue:info(Q, [messages]))
             end),
    ok.
