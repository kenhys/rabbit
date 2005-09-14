require "forwardable"

require "rabbit/menu"
require "rabbit/keys"
require "rabbit/renderer/pixmap"

module Rabbit
  module Renderer
    
    class DrawingArea
      include Base
      include Keys

      extend Forwardable
    
      @@color_table = {}
      
      def_delegators(:@pixmap, :foreground, :background)
      def_delegators(:@pixmap, :foreground=, :background=)
      def_delegators(:@pixmap, :background_image, :background_image=)
      
      def_delegators(:@pixmap, :draw_slide, :draw_line, :draw_rectangle)
      def_delegators(:@pixmap, :draw_arc, :draw_circle, :draw_layout)
      def_delegators(:@pixmap, :draw_pixbuf, :draw_polygon)

      def_delegators(:@pixmap, :draw_cube, :draw_sphere, :draw_cone)
      def_delegators(:@pixmap, :draw_torus, :draw_tetrahedron)
      def_delegators(:@pixmap, :draw_octahedron, :draw_dodecahedron)
      def_delegators(:@pixmap, :draw_icosahedron, :draw_teapot)
      
      def_delegators(:@pixmap, :gl_compile, :gl_call_list)
    
      def_delegators(:@pixmap, :make_color, :to_rgb)

      def_delegators(:@pixmap, :to_pixbuf)

      def_delegators(:@pixmap, :clear_pixmap, :clear_pixmaps)
      def_delegators(:@pixmap, :clear_theme)

      def_delegators(:@pixmap, :filename, :filename=)
      
      BUTTON_PRESS_ACCEPTING_TIME = 250

      def initialize(canvas)
        super
        @current_cursor = nil
        @blank_cursor = nil
        @caching = nil
        @comment_initialized = false
        @button_handling = false
        init_progress
        clear_button_handler
        init_drawing_area
        init_pixmap(1, 1)
        init_comment_log_window
      end
      
      def attach_to(window)
        @window = window
        @hbox = Gtk::HBox.new
        @vbox = Gtk::VBox.new
        @vbox.pack_start(@area, true, true, 0)
        @area.show
        @vbox.pack_end(@comment_log_window, false, false, 0)
        @hbox.pack_end(@vbox, true, true, 0)
        init_comment_view_canvas
        init_comment_view_frame
        @hbox.pack_start(@comment_view_frame.window, false, false, 0)
        @window.add(@hbox)
        @hbox.show
        @vbox.show
        set_configure_event
      end
    
      def detach_from(window)
        window.remove(@area)
        window.signal_handler_disconnect(@connect_signal_id)
        @window = nil
      end
    
      def width
        if @drawable
          @drawable.size[0]
        end
      end
      
      def height
        if @drawable
          @drawable.size[1]
        end
      end

      def destroy
        @area.destroy
      end
      
      def post_apply_theme
        @pixmap.post_apply_theme
        update_menu
        @area.queue_draw
      end
      
      def post_move(index)
        @pixmap.post_move(index)
        update_title
        @area.queue_draw
      end
      
      def post_fullscreen
        set_cursor(blank_cursor)
        clear_pixmaps
        update_menu
      end
      
      def post_unfullscreen
        set_cursor(nil)
        clear_pixmaps
        update_menu
      end
      
      def post_iconify
        update_menu
      end
      
      def redraw
        clear_pixmap
        @area.queue_draw
      end
      
      
      def post_parse_rd
        clear_button_handler
        update_title
        update_menu
      end
      
      def index_mode_on
        @drawable.cursor = nil
      end
      
      def index_mode_off
        @drawable.cursor = @current_cursor
      end
      
      def post_toggle_index_mode
        update_menu
        @area.queue_draw
      end
      
      def make_layout(text)
        attrs, text = Pango.parse_markup(text)
        layout = create_pango_layout(text)
        layout.set_attributes(attrs)
        layout
      end

      def create_pango_context
        @area.create_pango_context
      end

      def create_pango_layout(text)
        @area.create_pango_layout(text)
      end
      
      def pre_print(slide_size)
        start_progress(slide_size)
      end

      def printing(i)
        update_progress(i)
      end

      def post_print
        end_progress
      end

      def pre_to_pixbuf(slide_size)
        start_progress(slide_size)
      end

      def to_pixbufing(i)
        update_progress(i)
      end
      
      def post_to_pixbuf
        end_progress
      end

      def pre_cache_all_slides(slide_size)
        @caching = true
        start_progress(slide_size)
      end

      def caching_all_slides(i, canvas)
        update_progress(i)
        unless @pixmap.has_key?(@canvas.slides[i])
          @pixmap[@canvas.slides[i]] = canvas.renderer[canvas.slides[i]]
        end
      end
      
      def post_cache_all_slides(canvas)
        end_progress
        @caching = false
        @pixmap.clear_pixmaps
        @canvas.slides.each_with_index do |slide, i|
          @pixmap[slide] = canvas.renderer[canvas.slides[i]]
        end
        @area.queue_draw
      end

      def confirm_quit
        case confirm_dialog
        when Gtk::MessageDialog::RESPONSE_OK
          @canvas.quit
        when Gtk::MessageDialog::RESPONSE_CANCEL
        end
      end
      
      def progress_foreground=(color)
        super
        setup_progress_color
      end
      
      def progress_background=(color)
        super
        setup_progress_color
      end

      def display?
        true
      end

      def toggle_white_out
        super
        update_menu
        @area.queue_draw
      end

      def toggle_black_out
        super
        update_menu
        @area.queue_draw
      end

      def toggle_comment_frame
        ensure_comment
        if @comment_frame.visible?
          @comment_frame.hide
        else
          adjust_comment_frame
          @comment_frame.show
        end
      end

      def toggle_comment_view
        ensure_comment
        if @comment_log_window.visible?
          @comment_log_window.hide_all
          @comment_view_frame.hide
        else
          adjust_comment_view
          @comment_log_window.show_all
          @comment_view_frame.show
          @comment_view_canvas.parse_rd(@canvas.comment_source)
          @comment_view_canvas.move_to_last
        end
        adjust_comment_frame
      end

      def update_comment(source, &block)
        ensure_comment
        error_occurred = parse_comment(source, &block)
        unless error_occurred
          @comment_canvas.move_to_last
          reset_comment_log
          if @comment_view_frame.visible?
            @comment_view_frame.parse_rd(source)
            @comment_view_canvas.move_to_last
          end
        end
      end
      
      def post_init_gui
        @comment_log_window.hide
        @comment_view_frame.hide if @comment_view_frame
      end
      
      private
      def can_create_pixbuf?
        true
      end
      
      def init_pixmap(w=width, h=height)
        @pixmap = Renderer::Pixmap.new(@canvas, w, h)
        @pixmap.setup_event(self)
      end

      def parse_comment(source)
        error_occurred = false
        @comment_canvas.parse_rd(source) do |error|
          error_occurred = true
          if block_given?
            yield(error)
          else
            @comment_canvas.logger.warn(error)
          end
        end
        error_occurred
      end
      
      def ensure_comment
        unless @comment_initialized
          init_comment
          @comment_initialized = true
        end
      end

      def init_comment
        init_comment_canvas
        init_comment_frame
        @comment_canvas.parse_rd(@canvas.comment_source)
      end
      
      def init_comment_frame
        @comment_frame = Frame.new(@comment_canvas.logger, @comment_canvas)
        w, h = suggested_comment_frame_size
        @comment_frame.init_gui(w, h, false, Gtk::Window::POPUP)
        @comment_frame.hide
      end

      def init_comment_canvas
        @comment_canvas = Canvas.new(@canvas.logger, DrawingArea)
      end

      def init_comment_view_frame
        args = [@comment_view_canvas.logger, @comment_view_canvas]
        @comment_view_frame = EmbedFrame.new(*args)
        @comment_view_frame.init_gui(-1, -1, false)
        @comment_view_frame.hide
      end
      
      def init_comment_view_canvas
        @comment_view_canvas = Canvas.new(@canvas.logger, RotateDrawingArea)
      end
      
      def clear_button_handler
        @button_handler_thread = nil
        @button_handler = []
      end

      def clear_progress_color
        super
        setup_progress_color
      end

      def update_menu
        @menu = Menu.new(@canvas)
      end

      def update_title
        @canvas.update_title(@canvas.slide_title)
      end

      def init_progress
        @progress_window = Gtk::Window.new(Gtk::Window::POPUP)
        @progress_window.app_paintable = true
        @progress = Gtk::ProgressBar.new
        @progress.show_text = true
        @progress_window.add(@progress)
      end

      def setup_progress_color
        return unless @progress
        style = @progress.style.copy
        if @progress_foreground
          style.set_bg(Gtk::STATE_NORMAL, *to_rgb(@progress_foreground))
        end
        if @progress_background
          style.set_bg(Gtk::STATE_PRELIGHT, *to_rgb(@progress_background))
        end
        @progress.style = style
      end
      
      COMMENT_LOG_COMMENT_COLUMN = 0

      def reset_comment_log
        @comment_log_model.clear
        @comment_canvas.slides[1..-1].each do |slide|
          iter = @comment_log_model.prepend
          iter.set_value(COMMENT_LOG_COMMENT_COLUMN, slide.headline.text)
        end
      end
      
      def init_comment_log_model
        @comment_log_model = Gtk::ListStore.new(String)
      end

      def init_comment_log_view
        init_comment_log_model
        @comment_log_view = Gtk::TreeView.new(@comment_log_model)
        @comment_log_view.can_focus = false
        @comment_log_view.rules_hint = true
        @comment_log_renderer_comment = Gtk::CellRendererText.new
        args = [
          _("comment"),
          @comment_log_renderer_comment,
          {"text" => COMMENT_LOG_COMMENT_COLUMN}
        ]
        @comment_log_column_comment = Gtk::TreeViewColumn.new(*args)
        @comment_log_view.append_column(@comment_log_column_comment)
      end
      
      def init_comment_log_window
        init_comment_log_view
        @comment_log_window = Gtk::ScrolledWindow.new
        @comment_log_window.set_policy(Gtk::POLICY_AUTOMATIC,
                                       Gtk::POLICY_AUTOMATIC)
        @comment_log_window.add(@comment_log_view)
      end
      
      def init_drawing_area
        @area = Gtk::DrawingArea.new
        @area.set_can_focus(true)
        event_mask = Gdk::Event::BUTTON_PRESS_MASK
        event_mask |= Gdk::Event::BUTTON_RELEASE_MASK
        event_mask |= Gdk::Event::BUTTON1_MOTION_MASK 
        event_mask |= Gdk::Event::BUTTON2_MOTION_MASK 
        event_mask |= Gdk::Event::BUTTON3_MOTION_MASK 
        @area.add_events(event_mask)
        set_realize
        set_key_press_event
        set_button_event
        set_motion_notify_event
        set_expose_event
        set_scroll_event
      end
      
      def set_realize
        @area.signal_connect("realize") do |widget, event|
          @drawable = widget.window
          @foreground = Gdk::GC.new(@drawable)
          @background = Gdk::GC.new(@drawable)
          @background.set_foreground(widget.style.bg(Gtk::STATE_NORMAL))
          @white = Gdk::GC.new(@drawable)
          @white.set_foreground(make_color("white"))
          @black = Gdk::GC.new(@drawable)
          @black.set_foreground(make_color("black"))
          init_pixmap
        end
      end
      
      def set_key_press_event
        @area.signal_connect("key_press_event") do |widget, event|
          handled = false

          if event.state.control_mask?
            handled = handle_key_with_control(event)
          end
          
          unless handled
            handled = handle_key(event)
          end
          
          handled
        end
      end

      def set_button_event
        last_button_press_event = nil
        @area.signal_connect("button_press_event") do |widget, event|
          last_button_press_event = event
          call_hook_procs(@button_press_hook_procs, event)
        end

        @area.signal_connect("button_release_event") do |widget, event|
          handled = call_hook_procs(@button_release_hook_procs,
                                    event, last_button_press_event)
          if handled
            clear_button_handler
          else
            handled = handle_button_release(event, last_button_press_event)
          end
          widget.grab_focus
          handled
        end
      end

      def set_motion_notify_event
        @area.signal_connect("motion_notify_event") do |widget, event|
          call_hook_procs(@motion_notify_hook_procs, event)
        end
      end
      
      def set_expose_event
        prev_width = prev_height = nil
        @area.signal_connect("expose_event") do |widget, event|
          unless @caching
            @canvas.reload_source
            if @drawable
              if [prev_width, prev_height] != [width, height]
                @canvas.reload_theme
                prev_width, prev_height = width, height
              end
            end
          end
          
          if @white_out
            @drawable.draw_rectangle(@white, true, 0, 0, width, height)
          elsif @black_out
            @drawable.draw_rectangle(@black, true, 0, 0, width, height)
          else
            slide = @canvas.current_slide
            if slide
              unless @pixmap.has_key?(slide)
                @pixmap.width = width
                @pixmap.height = height
                slide.draw(@canvas)
              end
              @drawable.draw_drawable(@foreground, @pixmap[slide],
                                      0, 0, 0, 0, -1, -1)
            end
          end
        end
      end
      
      def set_scroll_event
        @area.signal_connect("scroll_event") do |widget, event|
          case event.direction
          when Gdk::EventScroll::Direction::UP
            @canvas.move_to_previous_if_can
          when Gdk::EventScroll::Direction::DOWN
            @canvas.move_to_next_if_can
          end
        end
      end
      
      def set_configure_event
        id = @window.signal_connect("configure_event") do |widget, event|
          args = [event.x, event.y, event.width, event.height]
          adjust_comment_frame(*args)
          adjust_comment_view(*args)
          adjust_progress_window(*args)
          false
        end
        @configure_signal_id = id
      end
      
      def set_cursor(cursor)
        @current_cursor = @drawable.cursor = cursor
      end
      
      def blank_cursor
        if @blank_cursor.nil?
          source = Gdk::Pixmap.new(@drawable, 1, 1, 1)
          mask = Gdk::Pixmap.new(@drawable, 1, 1, 1)
          fg = @foreground.foreground
          bg = @background.foreground
          @blank_cursor = Gdk::Cursor.new(source, mask, fg, bg, 1, 1)
        end
        @blank_cursor
      end
      
      def calc_slide_number(key_event, base)
        val = key_event.keyval
        val += 10 if key_event.state.control_mask?
        val += 20 if key_event.state.mod1_mask?
        val - base
      end

      def handle_key(key_event)
        handled = true
        case key_event.keyval
        when *QUIT_KEYS
          if @canvas.processing?
            confirm_quit
          else
            @canvas.quit
          end
        when *MOVE_TO_NEXT_KEYS
          @canvas.move_to_next_if_can
        when *MOVE_TO_PREVIOUS_KEYS
          @canvas.move_to_previous_if_can
        when *MOVE_TO_FIRST_KEYS
          @canvas.move_to_first
        when *MOVE_TO_LAST_KEYS
          @canvas.move_to_last
        when Gdk::Keyval::GDK_0,
          Gdk::Keyval::GDK_1,
          Gdk::Keyval::GDK_2,
          Gdk::Keyval::GDK_3,
          Gdk::Keyval::GDK_4,
          Gdk::Keyval::GDK_5,
          Gdk::Keyval::GDK_6,
          Gdk::Keyval::GDK_7,
          Gdk::Keyval::GDK_8,
          Gdk::Keyval::GDK_9
          index = calc_slide_number(key_event, Gdk::Keyval::GDK_0)
          @canvas.move_to_if_can(index)
        when Gdk::Keyval::GDK_KP_0,
          Gdk::Keyval::GDK_KP_1,
          Gdk::Keyval::GDK_KP_2,
          Gdk::Keyval::GDK_KP_3,
          Gdk::Keyval::GDK_KP_4,
          Gdk::Keyval::GDK_KP_5,
          Gdk::Keyval::GDK_KP_6,
          Gdk::Keyval::GDK_KP_7,
          Gdk::Keyval::GDK_KP_8,
          Gdk::Keyval::GDK_KP_9
          index = calc_slide_number(key_event, Gdk::Keyval::GDK_KP_0)
          @canvas.move_to_if_can(index)
        when *TOGGLE_FULLSCREEN_KEYS
          @canvas.toggle_fullscreen
          @canvas.reload_theme
        when *RELOAD_THEME_KEYS
          @canvas.reload_theme
        when *SAVE_AS_IMAGE_KEYS
          thread do
            @canvas.save_as_image
          end
        when *ICONIFY_KEYS
          @canvas.iconify
        when *TOGGLE_INDEX_MODE_KEYS
          thread do
            @canvas.toggle_index_mode
          end
        when *CACHE_ALL_SLIDES_KEYS
          thread do
            @canvas.cache_all_slides
          end
        when *WHITE_OUT_KEYS
          toggle_white_out
        when *BLACK_OUT_KEYS
          toggle_black_out
        when *TOGGLE_COMMENT_FRAME_KEYS
          toggle_comment_frame
        when *TOGGLE_COMMENT_VIEW_KEYS
          toggle_comment_view
        else
          handled = false
        end
        handled
      end
      
      def handle_key_when_processing(key_event)
        case key_event.keyval
        when *QUIT_KEYS
          confirm_quit
        else
          @canvas.logger.info(_("processing..."))
        end
      end
      
      def handle_key_with_control(key_event)
        handled = true
        case key_event.keyval
        when *Control::REDRAW_KEYS
          @canvas.redraw
        when *Control::PRINT_KEYS
          thread do
            @canvas.print
          end
        else
          handled = false
        end
        handled
      end
      
      BUTTON_PRESS_HANDLER = {
        Gdk::Event::Type::BUTTON_PRESS => "handle_button_press",
        Gdk::Event::Type::BUTTON2_PRESS => "handle_button2_press",
        Gdk::Event::Type::BUTTON3_PRESS => "handle_button3_press",
      }
      
      def handle_button_release(event, last_button_press_event)
        press_event_type = last_button_press_event.event_type
        if BUTTON_PRESS_HANDLER.has_key?(press_event_type)
          __send__(BUTTON_PRESS_HANDLER[press_event_type],
                   last_button_press_event, event)
          start_button_handler
        end
        true
      end

      def handle_button_press(event, release_event)
        case event.button
        when 1, 5
          add_button_handler do
            @canvas.move_to_next_if_can
          end
        when 2, 4
          add_button_handler do
            @canvas.move_to_previous_if_can
          end
        when 3
          add_button_handler do
            @menu.popup(0, Gtk.current_event_time)
          end
        end
      end
      
      def handle_button2_press(event, release_event)
        add_button_handler do
          if @canvas.index_mode?
            index = @canvas.current_slide.slide_number(@canvas, event.x, event.y)
            if index
              @canvas.toggle_index_mode
              @canvas.move_to_if_can(index)
            end
          end
          clear_button_handler
        end
      end
      
      def handle_button3_press(event, release_event)
        add_button_handler do
          clear_button_handler
        end
      end
      
      def add_button_handler(handler=Proc.new)
        @button_handler.push(handler)
      end
      
      def call_button_handler
        @button_handler.pop.call until @button_handler.empty?
      end
      
      def start_button_handler
        if @button_handling
          @coming = true
        else
          @button_handling = true
          @coming = false
          Gtk.timeout_add(BUTTON_PRESS_ACCEPTING_TIME) do
            if @coming
              Gtk.timeout_add(BUTTON_PRESS_ACCEPTING_TIME) do
                call_button_handler
                @button_handling = false
                false
              end
            else
              call_button_handler
              @button_handling = false
            end
            false
          end
        end
      end

      def start_progress(max)
        return if max.zero?
        update_menu
        @progress_window.transient_for = @canvas.window
        @progress_window.show_all
        adjust_progress_window
        @progress.fraction = @progress_current = 0
        @progress_max = max.to_f
        Gtk.timeout_add(100) do
          @progress.fraction = @progress_current / @progress_max
          @progress_current < @progress_max
        end
      end

      def update_progress(i)
        @progress_current = i
      end

      def end_progress
        @progress_current = @progress_max
        Gtk.timeout_add(100) do
          @progress_window.hide
          update_menu
          false
        end
      end

      def adjust_progress_window(x=nil, y=nil, w=nil, h=nil)
        wx, wy = @canvas.window.position
        @progress_window.move(x || wx, y || wy)
      end

      def adjust_comment_frame(x=nil, y=nil, w=nil, h=nil)
        if @comment_initialized
          w, h = suggested_comment_frame_size(w, h)
          @comment_frame.resize(w, h)
          wx, wy = @canvas.window.position
          x ||= wx
          y ||= wy
          if @comment_view_frame.visible?
            x = x + @comment_view_frame.window.size_request[0]
          end
          y = y + height - h
          @comment_frame.window.move(x, y)
        end
      end

      def adjust_comment_view(x=nil, y=nil, w=nil, h=nil)
        ww, wh = suggested_comment_log_window_size(w, h)
        @comment_log_window.set_size_request(ww, wh)
        begin
          _, _, _, header_height = @comment_log_column_comment.cell_size
        rescue TypeError
          header_height = nil
        end
        if header_height
          text_size = (wh - header_height) * 0.5
        else
          text_size = wh * 0.4
        end
        @comment_log_renderer_comment.size = text_size * Pango::SCALE
      
        fw, fh = suggested_comment_view_frame_size(w, h)
        @comment_view_frame.set_size_request(fw, fh)
      end
      
      def suggested_comment_frame_size(w=nil, h=nil)
        w ||= @canvas.width
        h ||= @canvas.height
        [w / 10, h / 10]
      end
      
      def suggested_comment_log_window_size(w=nil, h=nil)
        h ||= @canvas.height
        [-1, h / 10]
      end
      
      def suggested_comment_view_frame_size(w=nil, h=nil)
        w ||= @canvas.width
        [w / 10, -1]
      end
      
      def confirm_dialog
        flags = Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT
        dialog_type = Gtk::MessageDialog::INFO
        buttons = Gtk::MessageDialog::BUTTONS_OK_CANCEL
        message = _("Now processing... Do you really quit?")
        dialog = Gtk::MessageDialog.new(nil, flags, dialog_type,
                                        buttons, message)
        result = dialog.run
        dialog.destroy
        result
      end

      def thread(&block)
        thread = Thread.new(&block)
        thread.priority = -10
      end

      def call_hook_procs(procs, *args)
        procs.find do |proc|
          proc.call(*args)
        end
      end
      
    end

    class RotateDrawingArea < DrawingArea

      attr_accessor :direction

      def initialize(canvas)
        super
        @direction = :right
      end

      def create_pango_context
        context = super
        setup_pango_context(context)
        context
      end

      def create_pango_layout(text)
        layout = super
        setup_pango_context(layout.context)
        layout
      end

      def attach_to(window)
        @window = window
        @window.add(@area)
        @area.show
      end
      
      def draw_layout(layout, x, y, color=nil, params={})
        super(layout, x, y, color, params)
      end
      
      private
      def setup_pango_context(context)
        matrix = Pango::Matrix.new
        if @direction == :right
          matrix.rotate!(270)
        else
          matrix.rotate!(90)
        end
        context.matrix = matrix
      end
      
    end

  end
end
