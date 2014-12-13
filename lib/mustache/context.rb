require 'mustache/context_miss'

class Mustache

  # A Context represents the context which a Mustache template is
  # executed within. All Mustache tags reference keys in the Context.
  class Context
    # Expect to be passed an instance of `Mustache`.
    def initialize(mustache)
      @stack = [mustache]
    end

    # A {{>partial}} tag translates into a call to the context's
    # `partial` method, which would be this sucker right here.
    #
    # If the Mustache view handling the rendering (e.g. the view
    # representing your profile page or some other template) responds
    # to `partial`, we call it and render the result.
    def partial(name, indentation = '')
      # Look for the first Mustache in the stack.
      mustache = mustache_in_stack

      # Indent the partial template by the given indentation.
      part = mustache.partial(name).to_s.gsub(/^/, indentation)

      # Call the Mustache's `partial` method and render the result.
      mustache.render(part, self)
    end

    # Find the first Mustache in the stack. If we're being rendered
    # inside a Mustache object as a context, we'll use that one.
    def mustache_in_stack
      @stack.find { |frame| frame.is_a?(Mustache) }
    end

    # Allows customization of how Mustache escapes things.
    #
    # Returns a String.
    def escapeHTML(str)
      mustache_in_stack.escapeHTML(str)
    end

    # Adds a new object to the context's internal stack.
    #
    # Returns the Context.
    def push(new)
      @stack.unshift(new)
      self
    end

    # Removes the most recently added object from the context's
    # internal stack.
    #
    # Returns the Context.
    def pop
      @stack.shift
      self
    end

    # Can be used to add a value to the context in a hash-like way.
    #
    # context[:name] = "Chris"
    def []=(name, value)
      push(name => value)
    end

    # Alias for `fetch`.
    def [](name)
      fetch(name, nil)
    end

    # Do we know about a particular key? In other words, will calling
    # `context[key]` give us a result that was set. Basically.
    def has_key?(key)
      !!fetch(key, false)
    rescue ContextMiss
      false
    end

    # Similar to Hash#fetch, finds a value by `name` in the context's
    # stack. You may specify the default return value by passing a
    # second parameter.
    #
    # If no second parameter is passed (or raise_on_context_miss is
    # set to true), will raise a ContextMiss exception on miss.
    def fetch(name, default = :__raise)
      @stack.each do |frame|
        # Prevent infinite recursion.
        next if frame == self

        value = find(frame, name, :__missing)
        return value if value != :__missing
      end

      if default == :__raise || mustache_in_stack.raise_on_context_miss?
        raise ContextMiss.new("Can't find #{name} in #{@stack.inspect}")
      else
        default
      end
    end

    # Finds a key in an object, using whatever method is most
    # appropriate. If the object is a hash, does a simple hash lookup.
    # If it's an object that responds to the key as a method call,
    # invokes that method. You get the idea.
    #
    # @param [Object] obj The object to perform the lookup on.
    # @param [String,Symbol] key The key whose value you want
    # @param [Object] default An optional default value, to return if the key is not found.
    #
    # @return [Object] The value of key in object if it is found, and default otherwise.
    def find(obj, key, default = nil)
      if obj.respond_to?(:to_hash)
        return find_in_hash(obj, key, default)
      end

      key = to_tag(key)
      return default unless obj.respond_to?(key)

      meth = obj.method(key) rescue proc { obj.send(key) }
      meth.arity == 1 ? meth.to_proc : meth.call
    end


    private


    # If a class, we need to find tags (methods) per Parser::ALLOWED_CONTENT.
    def to_tag key
      key.to_s.include?('-') ? key.to_s.tr('-', '_') : key
    end

    def find_in_hash obj, key, default
      return obj[key]      if obj.has_key?(key)
      return obj[key.to_s] if obj.has_key?(key.to_s)

      obj.fetch(key, default)
    end
  end
end
