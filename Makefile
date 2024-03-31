
.PHONY: test
test:
	rm -f test/usr/local/bin/*
	cp -a src/scripts/* test/usr/local/bin/
	chmod 0755 test/usr/local/bin/*
