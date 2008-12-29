module OmniDataObjects
  class SourceFilePair
    attr_reader :h, :m
    def initialize(h,m)
      @h = h
      @m = m
    end
    def br
      h.br
      m.br
    end
  end
end
