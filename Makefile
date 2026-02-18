.PHONY: docker-build docker-run-it 

CUID := $(shell id -u)
CGID := $(shell id -g)
CWD  := $(abspath $(dir $$PWD))


docker-build:
	docker build -t iic-osic-tools-minus:latest .

docker-run-it:
	docker run -it \
			   --user ${CUID}:${CGID} \
			   -e "UID=${CUID}" \
			   -e "GID=${CGID}" \
			   -v /etc/group:/etc/group:ro \
               -v /etc/passwd:/etc/passwd:ro \
               -v /etc/shadow:/etc/shadow:ro \
			   -v ~/.cache/:/headless/.cache:rw \
			   -v $(CWD):/foss/designs/spi-imp \
			    iic-osic-tools-minus:latest -s /bin/bash
