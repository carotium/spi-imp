FROM hpretl/iic-osic-tools:2025.07

RUN pip install --upgrade pip && \
    pip install "cython<3.0.0" wheel && \
    pip install "PyYAML==5.2" --no-build-isolation && \
    pip install cocotb==2.0.0 && \
    pi install git+https://github.com/Intuity/forastero

WORKDIR /foss/designs/spi-imp