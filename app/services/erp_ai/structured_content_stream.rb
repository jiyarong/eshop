module ErpAI
  class StructuredContentStream
    CONTENT_PREFIX = /\A\s*\{\s*"content"\s*:\s*"/m
    ESCAPES = {
      '"' => '"',
      "\\" => "\\",
      "/" => "/",
      "b" => "\b",
      "f" => "\f",
      "n" => "\n",
      "r" => "\r",
      "t" => "\t"
    }.freeze

    def initialize(&on_content)
      @on_content = on_content
      @buffer = +""
      @last_content = nil
    end

    def append(delta)
      return if delta.blank?

      @buffer << delta
      content = partial_content
      return if content.nil? || content == @last_content

      @last_content = content
      @on_content.call(content)
    end

    private

    def partial_content
      match = CONTENT_PREFIX.match(@buffer)
      return unless match

      decode_json_string(@buffer[match.end(0)..])
    end

    def decode_json_string(source)
      decoded = +""
      index = 0

      while index < source.length
        character = source[index]
        return decoded if character == '"'

        if character != "\\"
          decoded << character
          index += 1
          next
        end

        escape = source[index + 1]
        break unless escape

        if escape == "u"
          hex = source[(index + 2), 4]
          break unless hex&.match?(/\A[0-9a-fA-F]{4}\z/)

          codepoint = hex.to_i(16)
          if codepoint.between?(0xD800, 0xDBFF)
            low_surrogate = source[(index + 6), 6]
            match = /\A\\u([0-9a-fA-F]{4})\z/.match(low_surrogate.to_s)
            break unless match

            low_codepoint = match[1].to_i(16)
            break unless low_codepoint.between?(0xDC00, 0xDFFF)

            codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low_codepoint - 0xDC00)
            index += 12
          else
            index += 6
          end
          decoded << [ codepoint ].pack("U")
        elsif ESCAPES.key?(escape)
          decoded << ESCAPES.fetch(escape)
          index += 2
        else
          index += 2
        end
      end

      decoded
    end
  end
end
