group "default" {
  targets = ["agy-elixir-docker"]
}

target "elixir-docker" {
  context = "./templates/agy-elixir"
  target = "elixir-docker"
  tags = ["praialabs/sandbox-templates:elixir-docker"]
  pull = true
}

target "agy-elixir-docker" {
  context = "./templates/agy-elixir"
  target = "agy-elixir-docker"
  tags = ["praialabs/sandbox-templates:agy-elixir-docker"]
  pull = true
}
