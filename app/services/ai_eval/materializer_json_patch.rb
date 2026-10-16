# frozen_string_literal: true

module AiEval
  class MaterializerJsonPatch
    class Error < StandardError; end
    OPERATIONS = %w[add remove replace test copy move].freeze

    def apply(document, operations)
      result = document.deep_dup
      operations.each do |operation|
        operation = operation.deep_stringify_keys
        op = operation.fetch("op")
        path = operation.fetch("path")
        raise Error, "unsupported operation: #{op}" unless OPERATIONS.include?(op)
        case op
        when "test"
          raise Error, "test failed at #{path}" unless fetch(result, path) == operation.fetch("value")
        when "copy", "move"
          from = operation.fetch("from")
          if op == "move" && path.start_with?("#{from}/")
            raise Error, "cannot move a value into its own child"
          end
          value = fetch(result, from).deep_dup
          remove(result, from) if op == "move"
          result = add(result, path, value)
        when "add" then result = add(result, path, operation.fetch("value").deep_dup)
        when "remove" then result = remove(result, path)
        when "replace"
          fetch(result, path)
          result = replace(result, path, operation.fetch("value").deep_dup)
        end
      end
      result
    rescue KeyError => error
      raise Error, "patch member or path is missing: #{error.key}"
    end

    private

    def tokens(pointer)
      raise Error, "JSON Pointer must start with /" unless pointer.is_a?(String) && (pointer.empty? || pointer.start_with?("/"))
      raise Error, "invalid JSON Pointer escape" if pointer.match?(/~(?:[^01]|$)/)
      pointer.split("/", -1).drop(1).map { |token| token.gsub("~1", "/").gsub("~0", "~") }
    end

    def index(array, token, allow_end: false)
      return array.length if allow_end && token == "-"
      raise Error, "invalid array index: #{token}" unless token.match?(/\A(?:0|[1-9]\d*)\z/)
      value = token.to_i
      limit = allow_end ? array.length : array.length - 1
      raise Error, "array index out of bounds: #{token}" if value > limit
      value
    end

    def child(container, token)
      case container
      when Hash then container.fetch(token)
      when Array then container.fetch(index(container, token))
      else raise Error, "patch path is not a container"
      end
    end

    def fetch(document, path)
      tokens(path).reduce(document) { |current, token| child(current, token) }
    end

    def parent(document, path)
      parts = tokens(path)
      return [nil, nil] if parts.empty?
      key = parts.pop
      [parts.reduce(document) { |current, token| child(current, token) }, key]
    end

    def add(document, path, value)
      container, key = parent(document, path)
      return value if container.nil?
      case container
      when Hash then container[key] = value
      when Array then container.insert(index(container, key, allow_end: true), value)
      else raise Error, "patch path is not a container"
      end
      document
    end

    def remove(document, path)
      container, key = parent(document, path)
      return nil if container.nil?
      case container
      when Hash
        container.fetch(key)
        container.delete(key)
      when Array then container.delete_at(index(container, key))
      else raise Error, "patch path is not a container"
      end
      document
    end

    def replace(document, path, value)
      container, key = parent(document, path)
      return value if container.nil?
      case container
      when Hash then container[key] = value
      when Array then container[index(container, key)] = value
      else raise Error, "patch path is not a container"
      end
      document
    end
  end
end
