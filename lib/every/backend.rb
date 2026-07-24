module Every
  # Platform dispatch: launchd on macOS, systemd user timers on Linux.
  # Both backends implement the same interface:
  #   write(name, schedule)  enable(name)  disable(name)
  #   delete_units(name)     loaded?(name) unit_path(name)
  module Backend
    module_function

    def current
      RUBY_PLATFORM.include?("darwin") ? Launchd : Systemd
    end
  end
end
