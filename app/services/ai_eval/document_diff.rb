module AiEval
  class DocumentDiff
    def self.call(before, after, path = "")
      if before.is_a?(Hash) && after.is_a?(Hash)
        (before.keys | after.keys).flat_map do |key|
          pointer = "#{path}/#{key.to_s.gsub('~', '~0').gsub('/', '~1')}"
          if !before.key?(key)
            [{ path: pointer, before: nil, after: after[key], operation: "add" }]
          elsif !after.key?(key)
            [{ path: pointer, before: before[key], after: nil, operation: "remove" }]
          else
            call(before[key], after[key], pointer)
          end
        end
      elsif before == after
        []
      else
        [{ path: path, before: before, after: after, operation: "replace" }]
      end
    end
  end
end
