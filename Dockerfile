# syntax=docker/dockerfile:1

ARG PYTHON_VERSION=3.11.9
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS base

# Prevents Python from writing pyc files.
ENV PYTHONDONTWRITEBYTECODE=1

# Keeps Python from buffering stdout and stderr to avoid situations where
# the application crashes without emitting any logs due to buffering.
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install python3 and pip
RUN dnf install -y python3.11 python3-pip && \
    dnf clean all

COPY /src/requirements.txt .

# Download dependencies as a separate step to take advantage of Docker's caching.
# Leverage a cache mount to /root/.cache/pip to speed up subsequent builds.
# Leverage a bind mount to requirements.txt to avoid having to copy them into
# into this layer.
RUN --mount=type=cache,target=/root/.cache/pip \
--mount=type=bind,source=/src/requirements.txt,target=requirements.txt \
python3 -m pip install -r requirements.txt

# Copy the source code into the container.
COPY /src/ .

# Create data directory and set permissions for nobody user
RUN mkdir -p /data && \
    chown -R nobody:nobody /data

# Switch to the non-privileged user to run the application.
USER nobody

# Run app.py when the container launches
CMD ["python3", "app.py"]