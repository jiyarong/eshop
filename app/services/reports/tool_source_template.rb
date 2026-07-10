module Reports
  class ToolSourceTemplate
    BODY_PATTERN = /<body[^>]*>(.*)<\/body>/mi
    STYLE_PATTERN = /<style[^>]*>(.*)<\/style>/mi
    EXTERNAL_SCRIPT_PATTERN = /<script[^>]+src="([^"]+)"[^>]*><\/script>/mi
    INLINE_SCRIPT_PATTERN = /<script(?![^>]+src=)[^>]*>(.*?)<\/script>/mi

    def initialize(path:, scope_class:)
      @source = File.read(path)
      @scope_class = scope_class
    end

    def body_html
      @body_html ||= @source.match(BODY_PATTERN)&.captures&.first.to_s.strip
    end

    def external_script_urls
      @external_script_urls ||= @source.scan(EXTERNAL_SCRIPT_PATTERN).flatten
    end

    def scoped_style_content
      @scoped_style_content ||= scope_css(@source.match(STYLE_PATTERN)&.captures&.first.to_s)
    end

    def raw_inline_script_content
      @raw_inline_script_content ||= @source.scan(INLINE_SCRIPT_PATTERN).flatten.last.to_s
    end

    def inline_script_content(initializer_name:, selector_replacements: {}, wrap: false, export_statements: [])
      script = raw_inline_script_content.dup
      script = script.sub(
        "document.addEventListener('DOMContentLoaded', () => {",
        "function #{initializer_name}() {"
      )
      script = script.sub(
        "window.addEventListener('DOMContentLoaded', () => {",
        "function #{initializer_name}() {"
      )
      script = script.sub(/(\n\s*)\}\);\s*\z/, "\\1}\n\\1#{initializer_name}();")

      selector_replacements.each do |original, replacement|
        script = script.gsub(original, replacement)
      end

      return script unless wrap

      wrapped_sections = [script.strip, export_statements.join("\n").strip].reject(&:blank?)
      "(function() {\n#{wrapped_sections.join("\n\n")}\n})();"
    end

    private

    def scope_css(css)
      output = +""
      index = 0

      while index < css.length
        if css[index, 2] == "/*"
          comment_end = css.index("*/", index + 2)
          comment_end = css.length - 2 if comment_end.nil?
          output << css[index..(comment_end + 1)]
          index = comment_end + 2
          next
        end

        if css[index] == "@"
          boundary_index = find_boundary(css, index, ["{", ";"])
          break if boundary_index.nil?

          if css[boundary_index] == ";"
            output << css[index..boundary_index]
            index = boundary_index + 1
            next
          end

          block_end = find_matching_brace(css, boundary_index)
          break if block_end.nil?

          prelude = css[index...boundary_index]
          body = css[(boundary_index + 1)...block_end]
          output << prelude << "{"
          output << (scoping_at_rule?(prelude) ? scope_css(body) : body)
          output << "}"
          index = block_end + 1
          next
        end

        boundary_index = find_boundary(css, index, ["{"])
        break if boundary_index.nil?

        block_end = find_matching_brace(css, boundary_index)
        break if block_end.nil?

        selectors = css[index...boundary_index]
        body = css[(boundary_index + 1)...block_end]
        output << scope_selector_list(selectors) << "{" << body << "}"
        index = block_end + 1
      end

      if index < css.length
        output << css[index..]
      end

      output
    end

    def scope_selector_list(selectors)
      split_top_level(selectors, ",").map { |selector| scope_selector(selector.strip) }.join(", ")
    end

    def split_top_level(text, delimiter)
      parts = []
      current = +""
      parentheses_depth = 0
      brackets_depth = 0
      quote = nil
      index = 0

      while index < text.length
        character = text[index]
        next_character = text[index + 1]

        if quote
          current << character
          if character == "\\" && next_character
            current << next_character
            index += 2
            next
          end
          quote = nil if character == quote
          index += 1
          next
        end

        if character == "/" && next_character == "*"
          comment_end = text.index("*/", index + 2)
          comment_end = text.length - 2 if comment_end.nil?
          current << text[index..(comment_end + 1)]
          index = comment_end + 2
          next
        end

        case character
        when "'", "\""
          quote = character
          current << character
        when "("
          parentheses_depth += 1
          current << character
        when ")"
          parentheses_depth -= 1 if parentheses_depth.positive?
          current << character
        when "["
          brackets_depth += 1
          current << character
        when "]"
          brackets_depth -= 1 if brackets_depth.positive?
          current << character
        else
          if character == delimiter && parentheses_depth.zero? && brackets_depth.zero?
            parts << current
            current = +""
          else
            current << character
          end
        end

        index += 1
      end

      parts << current if current.present?
      parts
    end

    def find_boundary(text, start_index, delimiters)
      parentheses_depth = 0
      brackets_depth = 0
      quote = nil
      index = start_index

      while index < text.length
        character = text[index]
        next_character = text[index + 1]

        if quote
          if character == "\\" && next_character
            index += 2
            next
          end
          quote = nil if character == quote
          index += 1
          next
        end

        if character == "/" && next_character == "*"
          comment_end = text.index("*/", index + 2)
          return nil if comment_end.nil?

          index = comment_end + 2
          next
        end

        case character
        when "'", "\""
          quote = character
        when "("
          parentheses_depth += 1
        when ")"
          parentheses_depth -= 1 if parentheses_depth.positive?
        when "["
          brackets_depth += 1
        when "]"
          brackets_depth -= 1 if brackets_depth.positive?
        else
          return index if delimiters.include?(character) && parentheses_depth.zero? && brackets_depth.zero?
        end

        index += 1
      end

      nil
    end

    def find_matching_brace(text, open_brace_index)
      depth = 1
      quote = nil
      index = open_brace_index + 1

      while index < text.length
        character = text[index]
        next_character = text[index + 1]

        if quote
          if character == "\\" && next_character
            index += 2
            next
          end
          quote = nil if character == quote
          index += 1
          next
        end

        if character == "/" && next_character == "*"
          comment_end = text.index("*/", index + 2)
          return nil if comment_end.nil?

          index = comment_end + 2
          next
        end

        case character
        when "'", "\""
          quote = character
        when "{"
          depth += 1
        when "}"
          depth -= 1
          return index if depth.zero?
        end

        index += 1
      end

      nil
    end

    def scoping_at_rule?(prelude)
      prelude.match?(/\A\s*@(?:container|document|layer|media|supports)\b/)
    end

    def scope_selector(selector)
      return ".#{@scope_class}" if selector == "body" || selector == ":root"
      return ".#{@scope_class}, .#{@scope_class} *" if selector == "*"

      selector = selector.gsub(/\bbody\b/, ".#{@scope_class}")
      selector = selector.gsub(":root", ".#{@scope_class}")
      return selector if selector.start_with?(".#{@scope_class}")

      ".#{@scope_class} #{selector}"
    end
  end
end
