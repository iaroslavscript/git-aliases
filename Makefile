
all: test

.PHONY: dev-setup
dev-setup: test/.venv/bin/activate
	python3 -m venv test/.venv
	python3 -m venv --upgrade-deps --upgrade test/.venv
	pip install -r src/jira-client/requirements.txt

.PHONY: test
test:
	rm -f test/usr/local/bin/*
	cp -a src/scripts/* test/usr/local/bin/
	chmod 0755 test/usr/local/bin/*

.PHONY: install
install:
	mkdir -p ~/.git-scripts
	cp src/scripts/* ~/.git-scripts/
	chmod +x ~/.git-scripts/git-*
	[ -f ~/.gitconfig ] && cp ~/.gitconfig ~/.gitconfig.bak || true
	cp src/gitconfig.tmpl ~/.gitconfig
