module D3D
  # Optional native acceleration through a DragonRuby Pro C extension
  # (app/d3d/ext/d3d_ext.c, built with bin/build-ext). The engine never needs
  # it: every native function has a pure Ruby fallback, and nothing native is
  # used until a game calls D3D::Native.load and it succeeds. Without a Pro
  # license, without a built library or on CRuby, load returns false and the
  # engine stays pure Ruby.
  module Native
    extend self

    LIBRARY = 'd3d_ext'

    # Loads native/<platform>/d3d_ext.* from the game dir. Returns true when
    # D3D::Ext is ready (enabled from then on), false otherwise.
    def load(library = LIBRARY)
      return enable if loaded?
      # DR.respond_to?(:ffi_misc) is false even where it works, so just call
      # it; any error from the loader ends up in the rescue below.
      return false unless Object.const_defined?(:DR)

      DR.ffi_misc.gtk_dlopen(library)
      loaded? ? enable : false
    rescue StandardError
      false
    end

    # True when the extension is loaded and not switched off.
    def enabled?
      @enabled == true
    end

    # Switches native code off (e.g. to compare against the Ruby fallback)
    # or back on; turning it on only works once the extension is loaded.
    def enabled=(value)
      @enabled = value && loaded? ? true : false
    end

    def loaded?
      D3D.constants.include?(:Ext)
    end

    private

    def enable
      @enabled = true
    end
  end
end
