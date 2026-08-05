%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          {Credo.Check.Design.TagTODO, exit_status: 2},
          {Credo.Check.Readability.StrictModuleLayout, order: [:moduledoc, :use, :alias, :require, :import]}
        ],
        disabled: [
          {Credo.Check.Refactor.MapInto, false}
        ]
      }
    }
  ]
}
