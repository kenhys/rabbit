require "tempfile"

require "poppler"

require "rabbit/element"
require "rabbit/parser/base"

module Rabbit
  module Parser
    class PDF < Base
      unshift_loader(self)
      class << self
        def match?(source)
          /\A%PDF-1\.\d\z/ =~ source.read.split(/\r?\n/, 2)[0]
        end
      end

      include Element
      def parse
        @pdf = Tempfile.new("rabbit-pdf")
        @pdf.binmode
        @pdf.print(@source.read)
        @pdf.close
        doc = Poppler::Document.new("file://#{@pdf.path}")

        title_page, *rest = doc.to_a

        @canvas << PopplerTitleSlide.new(title_page, doc)
        rest.each do |page|
          @canvas << PopplerSlide.new(page)
        end
      end
    end
  end
end