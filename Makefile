CONFIGURATION := debug

install:
	which pre-commit &> /dev/null || pip3 install pre-commit
	which swiftformat &> /dev/null || brew install swiftformat
	pre-commit install

format:
	pre-commit run --all-files

build:
	swift build -c $(CONFIGURATION) --product xccache-proxy

local.cp:
	cp .build/$(CONFIGURATION)/xccache-proxy ../xccache/libexec/
	cp .build/$(CONFIGURATION)/libSwiftPM.dylib ../xccache/libexec/
