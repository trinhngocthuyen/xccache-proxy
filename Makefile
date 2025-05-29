CONFIGURATION := debug

install:
	which pre-commit &> /dev/null || pip3 install pre-commit
	which swiftformat &> /dev/null || brew install swiftformat
	pre-commit install

format:
	pre-commit run --all-files

build:
	swift build -c $(CONFIGURATION) --product xccache-proxy
	cd .build/$(CONFIGURATION) && rm -rf xccache-proxy.zip && zip -r xccache-proxy.zip xccache-proxy
	mkdir -p artifacts && cp .build/$(CONFIGURATION)/xccache-proxy.zip artifacts/
