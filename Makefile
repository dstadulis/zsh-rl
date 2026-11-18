# SPDX-License-Identifier: MIT

.PHONY: all check lint test test-unit test-plugin test-pty install uninstall

all: test

lint:
	zsh -n rl.zsh zsh-rl.plugin.zsh functions/rl completions/_rl install.sh uninstall.sh tests/*.zsh
	test -x install.sh && test -x uninstall.sh

test-unit:
	zsh ./tests/rl.test.zsh

test-plugin:
	zsh ./tests/plugin_and_install.test.zsh

test-pty:
	python3 ./tests/pty_completion.test.py

test: lint test-unit test-plugin test-pty

check: test

install:
	./install.sh

uninstall:
	./uninstall.sh
