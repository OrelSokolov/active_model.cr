# ActiveModel::Callbacks — define_callbacks/set_callback/run_callbacks.
# Terminator semantics mirrored from ActiveSupport::Callbacks (the gem's
# engine, verified by oracle cb_order/cb_abort):
# - DEFAULT terminator: each before callback runs inside a catch; `throw
#   :abort` (mapped to Callbacks::Halt — Crystal has no throw/catch) halts
#   the chain: yield and afters are skipped.
# - CUSTOM terminator: receives the result proc and decides. If it never
#   calls the proc, the callback is SKIPPED (the gem quirk pinned by
#   oracle cb_abort — log [:yield], no :stopped). Deviation: the gem takes
#   a lambda, the port takes a method-name Symbol (typed lambdas can't be
#   written generically in Crystal).
#
# Architecture (Crystal 1.21): previous_def does not see module methods
# and cannot be used inside proc literals, so:
# - before/after callbacks chain via previous_def redefinitions of
#   __run_cb_befores_<kind>/__run_cb_afters_<kind> (declaration order =
#   run order, previous_def first);
# - around callbacks live in a runtime registry (class variable of Procs)
#   — around bodies need the inner block, which previous_def chains
#   cannot thread; __cb_around_step_<kind> recurses through the registry,
#   first registered around = outermost.
module ActiveModel
  module Callbacks
    class Halt < Exception
    end

    # Ruby's `throw :abort` — raises Halt, caught by the default terminator.
    def throw(tag : Symbol) : Nil
      if tag == :abort
        raise Halt.new
      else
        raise ArgumentError.new("uncaught throw #{tag.inspect}")
      end
    end

    # Default terminator: run the callback, halt on throw(:abort).
    def __cb_default_terminator(result : Proc(Nil)) : Bool
      result.call
      false
    rescue Halt
      true
    end

    # define_callbacks :save, terminator: :my_terminator
    macro define_callbacks(*names, terminator = nil)
      {% for name in names %}
        # Base run_callbacks planted on first define_callbacks so that
        # unknown kinds raise (and later kinds chain via previous_def).
        {% unless @type.methods.any? { |m| m.name.stringify == "run_callbacks" } %}
          def run_callbacks(kind : Symbol, &block : Proc(Nil)) : Nil
            raise ArgumentError.new("Unknown callback kind: #{kind}")
          end
        {% end %}

        @@__cb_around_{{name.id}} = Array(Proc({{ @type }}, Proc(Nil), Nil)).new

        def __cb_terminator_{{name.id}}(rl : Proc(Nil)) : Bool
          {% if terminator %}
            {{ terminator.id }}(rl)
          {% else %}
            __cb_default_terminator(rl)
          {% end %}
        end

        def __run_cb_befores_{{name.id}} : Bool
          false
        end

        def __run_cb_afters_{{name.id}} : Nil
        end

        # Recurse through the around registry; first registered around
        # is outermost.
        def __cb_around_step_{{name.id}}(i : Int32, inner : Proc(Nil)) : Nil
          if i >= @@__cb_around_{{name.id}}.size
            inner.call
          else
            @@__cb_around_{{name.id}}[i].call(self, ->{ __cb_around_step_{{name.id}}(i + 1, inner) })
          end
        end

        def __run_cb_{{name.id}}(&block : Proc(Nil)) : Nil
          halted = __run_cb_befores_{{name.id}}
          unless halted
            __cb_around_step_{{name.id}}(0, block)
            __run_cb_afters_{{name.id}}
          end
        end

        def run_callbacks(kind : Symbol, &block : Proc(Nil)) : Nil
          if kind == {{name}}
            __run_cb_{{name.id}}(&block)
          else
            previous_def(kind, &block)
          end
        end
      {% end %}
    end

    # set_callback :save, :before, :mark_before
    # set_callback :save, :around do ... yield ... end
    # set_callback :save, :after do ... end
    macro set_callback(name, timing, method = nil, &block)
      {% if timing.id.stringify == "before" %}
        def __run_cb_befores_{{name.id}} : Bool
          halted = previous_def
          unless halted
            {% if method %}
              rl = -> : Nil { {{method.id}} }
            {% else %}
              rl = -> : Nil { {{ block.body }} }
            {% end %}
            halted = __cb_terminator_{{name.id}}(rl)
          end
          halted
        end
      {% elsif timing.id.stringify == "after" %}
        def __run_cb_afters_{{name.id}} : Nil
          previous_def
          {% if method %}
            {{method.id}}
          {% else %}
            {{ block.body }}
          {% end %}
        end
      {% else %}
        # around: register a Proc in the class-body registry (executes at
        # program start, in declaration order) + the body method it calls.
        {% n = @type.methods.select { |m| m.name.stringify.starts_with?("__cb_around_body_") }.size %}
        @@__cb_around_{{name.id}} << ->(m : {{ @type }}, inner : Proc(Nil)) : Nil do
          m.__cb_around_body_{{name.id}}_{{n}} { inner.call }
        end

        def __cb_around_body_{{name.id}}_{{n}}(&inner : Proc(Nil)) : Nil
          {% if method %}
            {{method.id}}(&inner)
          {% else %}
            {{ block.body }}
          {% end %}
        end
      {% end %}
    end
  end
end
