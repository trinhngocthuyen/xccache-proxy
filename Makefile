install:
	which pre-commit &> /dev/null || pip3 install pre-commit
	which swiftformat &> /dev/null || brew install swiftformat
	pre-commit install

format:
	pre-commit run --all-files
