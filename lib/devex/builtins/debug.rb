# frozen_string_literal: true

# Hidden from help - useful for debugging context detection issues
# Access via: dx debug

desc "Debug context detection"

def run
  ctx = Devex::Context

  data = {
    tty:         {
      stdout:   $stdout.tty?,
      stderr:   $stderr.tty?,
      stdin:    $stdin.tty?,
      terminal: ctx.terminal?
    },
    streams:     {
      merged: ctx.streams_merged?,
      piped:  ctx.piped?
    },
    environment: {
      ci:               ctx.ci?,
      env:              ctx.env,
      agent_mode_env:   ctx.agent_mode_env?,
      dx_agent_mode:    ENV.fetch("DX_AGENT_MODE", nil),
      devex_agent_mode: ENV.fetch("DEVEX_AGENT_MODE", nil)
    },
    detection:   {
      agent_mode:  ctx.agent_mode?,
      interactive: ctx.interactive?,
      color:       ctx.color?
    },
    call_tree:   ctx.call_tree,
    overrides:   ctx.overrides
  }

  case output_format
  when :json, :yaml then Devex::Output.data(data, format: output_format)
  else
    $stdout.print Devex.render_template("debug", data)
  end
end
