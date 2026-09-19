variable "ASDF_VERSION" {
  default = "v0.20.0"
}

variable "ERLANG_VERSION" {
  default = "29.0.6"
}

variable "ELIXIR_VERSION" {
  default = "1.20.4-otp-29"
}

variable "NODEJS_VERSION" {
  default = "26.8.1"
}

variable "LEAN_VERSION" {
  default = "4.34.0"
}

variable "AGY_CACHEBUST" {
  default = ">=1.2.3"
}

group "default" {
  targets = ["agy-elixir-docker"]
}

target "agy-elixir-docker" {
  context = "./templates/agy-elixir"
  tags    = ["praialabs/sandbox-templates:agy-elixir-docker"]
  pull    = true
  args = {
    ASDF_VERSION   = "${ASDF_VERSION}"
    ERLANG_VERSION = "${ERLANG_VERSION}"
    ELIXIR_VERSION = "${ELIXIR_VERSION}"
    NODEJS_VERSION = "${NODEJS_VERSION}"
    LEAN_VERSION   = "${LEAN_VERSION}"
    AGY_CACHEBUST  = "${AGY_CACHEBUST}"
  }
}
