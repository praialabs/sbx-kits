variable "ASDF_VERSION" {
  default = "v0.20.0"
}

variable "ERLANG_VERSION" {
  default = "29.0.5"
}

variable "ELIXIR_VERSION" {
  default = "1.20.3-otp-29"
}

variable "NODEJS_VERSION" {
  default = "26.6.0"
}

variable "AGY_CACHEBUST" {
  default = ">=1.1.21"
}

group "default" {
  targets = ["agy-elixir-docker"]
}

target "elixir-docker" {
  context = "./templates/agy-elixir"
  target  = "elixir-docker"
  tags    = ["praialabs/sandbox-templates:elixir-docker"]
  pull    = true
  args = {
    ASDF_VERSION   = "${ASDF_VERSION}"
    ERLANG_VERSION = "${ERLANG_VERSION}"
    ELIXIR_VERSION = "${ELIXIR_VERSION}"
    NODEJS_VERSION = "${NODEJS_VERSION}"
  }
}

target "agy-elixir-docker" {
  inherits = ["elixir-docker"]
  target   = "agy-elixir-docker"
  tags     = ["praialabs/sandbox-templates:agy-elixir-docker"]
  args = {
    AGY_CACHEBUST = "${AGY_CACHEBUST}"
  }
}
