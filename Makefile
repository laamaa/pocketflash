PYTHON ?= python3
MODE ?= utility
PODMAN_CONNECTION ?=
export PODMAN_CONNECTION

.PHONY: help setup setup-podman toolchain rom rom-podman test test-host test-hdl package clean
help:
	@echo 'make setup                    start Apple container (macOS) or set up Podman'
	@echo 'make toolchain                pull, inspect and lock raetro/quartus:pocket'
	@echo 'make rom                      build the PocketFlash utility candidate (default)'
	@echo 'make package                  package the successful utility build'
	@echo 'make test                     host checks and HDL simulation (Icarus required)'
	@echo 'make test-host                host checks only'
	@echo 'make test-hdl                 HDL simulation only'
setup:
	$(PYTHON) tools/build.py setup
setup-podman:
	$(PYTHON) tools/build.py setup --runtime podman
toolchain:
	$(PYTHON) tools/build.py toolchain
rom:
	$(PYTHON) tools/build.py build --mode $(MODE)
rom-podman:
	$(PYTHON) tools/build.py build --mode $(MODE) --runtime podman
package:
	$(PYTHON) tools/package.py --mode $(MODE)
test: test-host test-hdl
test-host:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py' -v
test-hdl:
	$(PYTHON) tools/simulate.py
clean:
	$(PYTHON) tools/build.py clean
