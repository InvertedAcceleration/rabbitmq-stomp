PROJECT = rabbitmq_stomp

DEPS = ranch amqp_client
TEST_DEPS += rabbit

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

CT_OPTS += -ct_hooks cth_surefire

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk

# FIXME: Remove rabbitmq_test as TEST_DEPS from here for now.
TEST_DEPS := $(filter-out rabbitmq_test,$(TEST_DEPS))

include erlang.mk

# --------------------------------------------------------------------
# Testing.
# --------------------------------------------------------------------

STANDALONE_TEST_COMMANDS := \
	eunit:test([rabbit_stomp_test_util,rabbit_stomp_test_frame],[verbose])

pre-standalone-tests:: test-build test-tmpdir
	$(verbose) $(MAKE) -C test/deps/stomppy
	$(verbose) $(MAKE) -C test/deps/pika
