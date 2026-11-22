variable "BASE_IMAGE" {
  default = "docker.io/sbx/shell-docker-image:20261122-c279c9da843e51b135a5be3750ffcdf8078485b4@sha256:34d2de0c8dccd28ce55fd6ea8e3cd6123664f9d75abc9770cf24f43331373f3e"
}

variable "ASDF_VERSION" {
  default = "v0.20.0"
}

variable "ERLANG_VERSION" {
  default = "29.1.2"
}

variable "ELIXIR_VERSION" {
  default = "1.20.5-otp-29"
}

variable "NODEJS_VERSION" {
  default = "26.13.1"
}

variable "ZIG_VERSION" {
  default = "0.17.1"
}

variable "LEAN_VERSION" {
  default = "4.36.0"
}

variable "AGY_CACHEBUST" {
  default = ">=1.5.14"
}

group "default" {
  targets = ["agy-elixir-docker"]
}

target "agy-elixir-docker" {
  context = "./templates/agy-elixir"
  tags    = ["praialabs/sandbox-templates:agy-elixir-docker"]
  args = {
    BASE_IMAGE     = "${BASE_IMAGE}"
    ASDF_VERSION   = "${ASDF_VERSION}"
    ERLANG_VERSION = "${ERLANG_VERSION}"
    ELIXIR_VERSION = "${ELIXIR_VERSION}"
    NODEJS_VERSION = "${NODEJS_VERSION}"
    ZIG_VERSION    = "${ZIG_VERSION}"
    LEAN_VERSION   = "${LEAN_VERSION}"
    AGY_CACHEBUST  = "${AGY_CACHEBUST}"
  }
}
