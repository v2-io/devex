# frozen_string_literal: true

# Workaround for RubyGems' WebAuthn listener (rubygems 4.0.3,
# gemcutter_utilities/webauthn_listener.rb:53). A browser that opens a
# connection to the local port and closes it without sending anything
# (a speculative preconnect) makes `socket.gets` return nil, and the listener
# crashes with "undefined method 'split' for nil" before the real callback
# arrives. This skips such empty connections and keeps listening.
#
# Use, from the repo root:
#   RUBYOPT="-r$PWD/bin/webauthn_listener_patch.rb" gem push devex-X.Y.Z.gem
#
# Not part of the gem (bin/ is excluded in the gemspec). Delete once RubyGems
# guards the nil itself.
require "rubygems"
require "rubygems/gemcutter_utilities"

# Prepended to Gem::GemcutterUtilities::WebauthnListener (see above).
module SkipEmptyWebauthnConnections
  # Hands back only connections that actually sent a request line.
  class Server
    def initialize(server) = @server = server

    def accept
      loop do
        socket = @server.accept
        line   = socket.gets
        if line.nil?
          socket.close
          next
        end
        socket.ungetbyte(line)
        return socket
      end
    end

    def method_missing(name, ...) = @server.send(name, ...)
    def respond_to_missing?(name, include_private = false) = @server.respond_to?(name, include_private)
  end

  def wait_for_otp_code(server) = super(Server.new(server))
end

Gem::GemcutterUtilities::WebauthnListener.prepend(SkipEmptyWebauthnConnections)
