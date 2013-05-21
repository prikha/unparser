require 'spec_helper'

describe Unparser, 'spike' do


  PARSERS = IceNine.deep_freeze(
    '1.8' => Parser::Ruby18,
    '1.9' => Parser::Ruby19,
    '2.0' => Parser::Ruby20
  )

  RUBIES = PARSERS.keys.freeze

  def self.parser_for_ruby_version(version)
    PARSERS.fetch(version) do
      raise "Unrecognized Ruby version #{version}"
    end
  end

  def self.with_versions(versions)
    versions.each do |version|
      parser = parser_for_ruby_version(version)
      yield version, parser
    end
  end
  
  def self.strip(ruby)
    lines = ruby.lines
    line = lines.first
    match = /\A[ ]*/.match(line)
    length = match[0].length
    source = lines.map do |line|
      line[(length..-1)]
    end.join
    source.chomp
  end

  def assert_round_trip(input, parser)
    ast = parser.parse(input)
    generated = Unparser.unparse(ast)
    generated.should eql(input)
  end

  def self.assert_generates(ast, expected, versions = RUBIES)
    with_versions(versions) do |version, parser|
      it "should generate #{ast.inspect} as #{expected} under #{version}" do
        unless ast.kind_of?(Parser::AST::Node)
          ast = parser.parse(ast)
        end
        generated = Unparser.unparse(ast)
        generated.should eql(expected)
        ast = parser.parse(generated)
        Unparser.unparse(ast).should eql(expected)
      end
    end
  end

  def self.assert_round_trip(input, versions = RUBIES)
    with_versions(versions) do |version, parser|
      it "should round trip #{input.inspect} under #{version}" do
        assert_round_trip(input, parser)
      end
    end
  end

  def self.assert_source(input, versions = RUBIES)
    assert_round_trip(strip(input), versions)
  end

  context 'literal' do
    context 'fixnum' do
      assert_generates s(:int,  1),  '1'
      assert_generates s(:int, -1), '-1'
      assert_source '1'
      assert_source '0x1'
      assert_source '1_000'
      assert_source '1e10'
      assert_source '?c'
    end

    context 'string' do
      assert_generates %q("foo" "bar"), %q("foobar")
      assert_generates %q(%Q(foo"#{@bar})), %q("foo\"#{@bar}")
      assert_source %q("\"")
      assert_source %q("foo#{1}bar")
      assert_source %q("\"#{@a}")
    end

    context 'execute string' do
      assert_source '`foo`'
      assert_source '`foo#{@bar}`'
      assert_generates  '%x(\))', '`)`'
     #assert_generates  '%x(`)', '`\``'
      assert_source '`"`'
    end

    context 'symbol' do
      assert_generates s(:sym, :foo), ':foo'
      assert_generates s(:sym, :"A B"), ':"A B"'
      assert_source ':foo'
      assert_source ':"A B"'
      assert_source ':"A\"B"'
    end

    context 'regexp' do
      assert_source '/foo/'
      assert_source %q(/[^-+',.\/:@[:alnum:]\[\]\x80-\xff]+/)
      assert_source '/foo#{@bar}/'
      assert_source '/foo#{@bar}/im'
      assert_generates '%r(/)', '/\//'
      assert_generates '%r(\))', '/)/'
      assert_generates '%r(#{@bar}baz)', '/#{@bar}baz/'
    end

    context 'dynamic string' do
      assert_source %q("foo#{@bar}")
      assert_source     %q("fo\no#{bar}b\naz")
    end

    context 'dynamic symbol' do
      assert_source ':"foo#{bar}baz"'
      assert_source ':"fo\no#{bar}b\naz"'
      assert_source ':"#{bar}foo"'
      assert_source ':"foo#{bar}"'
    end

    context 'irange' do
      assert_generates '1..2', %q(1..2)
    end

    context 'erange' do
      assert_generates '1...2', %q(1...2)
    end

    context 'float' do
      assert_source '-0.1'
      assert_source '0.1'
      assert_generates s(:float, -0.1), '-0.1'
      assert_generates s(:float, 0.1), '0.1'
    end

    context 'array' do
      assert_source '[1, 2]'
      assert_source '[1]'
      assert_source '[]'
      assert_source '[1, *@foo]'
      assert_source '[*@foo, 1]',     RUBIES - %w(1.8)
      assert_source '[*@foo, *@baz]', RUBIES - %w(1.8)
    end

    context 'hash' do
      assert_source '{}'
      assert_source '{1 => 2}'
      assert_source '{1 => 2, 3 => 4}'
    end
  end

  context 'access' do
    assert_source '@a'
    assert_source '@@a'
    assert_source '$a'
    assert_source '$1'
    assert_source '$`'
    assert_source 'CONST'
    assert_source 'SCOPED::CONST'
    assert_source '::TOPLEVEL'
    assert_source '::TOPLEVEL::CONST'
  end

  context 'break' do
    assert_source 'break'
    assert_source 'break(a)'
  end

  context 'next' do
    assert_source 'next'
  end

  context 'retry' do
    assert_source 'retry'
  end

  context 'redo' do
    assert_source 'redo'
  end

  context 'singletons' do
    assert_source 'self'
    assert_source 'true'
    assert_source 'false'
    assert_source 'nil'
  end

  context 'magic keywords' do
    assert_generates  '__ENCODING__', 'Encoding::UTF_8', RUBIES - %w(1.8)
    assert_source '__FILE__'
    assert_source '__LINE__'
  end

  context 'assignment' do
    context 'single' do
      assert_source 'a = 1'
      assert_source '@a = 1'
      assert_source '@@a = 1'
      assert_source '$a = 1'
      assert_source 'CONST = 1'
    end

    context 'multiple' do
      assert_source 'a, b = 1, 2'
      assert_source 'a, *foo = 1, 2'
      assert_source 'a, * = 1, 2'
      assert_source '*foo = 1, 2'
      assert_source '@a, @b = 1, 2'
      assert_source 'a.foo, a.bar = 1, 2'
      assert_source 'a[0, 2]'
      assert_source 'a[0], a[1] = 1, 2'
      assert_source 'a[*foo], a[1] = 1, 2'
      assert_source '@@a, @@b = 1, 2'
      assert_source '$a, $b = 1, 2'
      assert_source 'a, b = foo'
    end
  end

  context 'return' do
    assert_source <<-RUBY
      return
    RUBY

    assert_source <<-RUBY
      return(1)
    RUBY
  end

  context 'send' do
    assert_source 'foo'
    assert_source 'self.foo'
    assert_source 'a.foo'
    assert_source 'A.foo'
    assert_source 'foo[1]'
    assert_source 'foo(1)'
    assert_source 'foo(bar)'
    assert_source 'foo(&block)'
    assert_source 'foo(*arguments)'
    assert_source "foo do\n\nend"
    assert_source "foo(1) do\n\nend"
    assert_source "foo do |a, b|\n\nend"
    assert_source "foo do |a, *b|\n\nend"
    assert_source "foo do |a, *|\n\nend"
    assert_source "foo do\n  bar\nend"
    assert_source 'foo.bar(*args)'

    assert_source <<-RUBY
      foo.bar do |(a, b), c|
        d
      end
    RUBY

    assert_source <<-RUBY
      foo.bar do |(a, b)|
        d
      end
    RUBY

    # Special cases
    assert_source '(1..2).max'

    assert_source 'foo.bar(*args)'
    assert_source 'foo.bar(*arga, foo, *argb)', RUBIES - %w(1.8)
    assert_source 'foo.bar(*args, foo)',        RUBIES - %w(1.8)
    assert_source 'foo.bar(foo, *args)'
    assert_source 'foo.bar(foo, *args, &block)'
    assert_source <<-RUBY
      foo(bar, *args)
    RUBY

    assert_source <<-RUBY
      foo(*args, &block)
    RUBY

    assert_source 'foo.bar(&baz)'
    assert_source 'foo.bar(:baz, &baz)'
    assert_source 'foo.bar=(:baz)'
    assert_source 'self.foo=(:bar)'
  end

  context 'begin; end' do
    assert_source <<-RUBY
      begin
        foo
        bar
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
        bar
      end.blah
    RUBY
  end

  context 'begin / rescue / ensure' do
    assert_source <<-RUBY
      begin
        foo
      ensure
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
      rescue
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        begin
          foo
          bar
        end
      rescue
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
      rescue Exception
        bar
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
      rescue => bar
        bar
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
      rescue Exception, Other => bar
        bar
      end
    RUBY

    assert_source <<-RUBY
      begin
        foo
      rescue Exception => bar
        bar
      end
    RUBY

    assert_source <<-RUBY
      begin
        bar
      rescue SomeError, *bar
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        bar
      rescue SomeError, *bar => exception
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        bar
      rescue *bar
        baz
      end
    RUBY

    assert_source <<-RUBY
      begin
        bar
      rescue *bar => exception
        baz
      end
    RUBY
  end

  context 'super' do
    assert_source 'super'

    assert_source <<-RUBY
      super do
        foo
      end
    RUBY

    assert_source 'super()'

    assert_source <<-RUBY
      super() do
        foo
      end
    RUBY

    assert_source 'super(a)'

    assert_source <<-RUBY
      super(a) do
        foo
      end
    RUBY

    assert_source 'super(a, b)'

    assert_source <<-RUBY
      super(a, b) do
        foo
      end
    RUBY

    assert_source 'super(&block)'
    assert_source 'super(a, &block)'
  end

  context 'undef' do
    assert_source 'undef :foo'
  end

  context 'BEGIN' do
    assert_source <<-RUBY
      BEGIN {
        foo
      }
    RUBY
  end

  context 'END' do
    assert_source <<-RUBY
      END {
        foo
      }
    RUBY
  end

  context 'alias' do
    assert_source <<-RUBY
      alias $foo $bar
    RUBY

    assert_source <<-RUBY
      alias foo bar
    RUBY
  end

  context 'yield' do
    context 'without arguments' do
      assert_source 'yield'
    end

    context 'with argument' do
      assert_source 'yield(a)'
    end

    context 'with arguments' do
      assert_source 'yield(a, b)'
    end
  end

  context 'if statement' do
    assert_source <<-RUBY
      if /foo/
        bar
      end
    RUBY

    assert_source <<-RUBY
      if 3
        9
      end
    RUBY

    assert_source <<-RUBY
      if 4
        5
      else
        6
      end
    RUBY

    assert_source <<-RUBY
      unless 3
        9
      end
    RUBY
  end

  context 'def' do
    context 'on instance' do

      assert_source <<-RUBY
        def foo
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar, baz)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar = true)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar, baz = true)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(*)
          bar
        end
      RUBY
      
      assert_source <<-RUBY
        def foo(*bar)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar, *baz)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(baz = true, *bor)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(baz = true, *bor, &block)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar, baz = true, *bor)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(&block)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def foo(bar, &block)
          bar
        end
      RUBY

      assert_source <<-RUBY
        def initialize(attributes, options)
          begin
            @attributes = freeze_object(attributes)
            @options = freeze_object(options)
            @attribute_for = Hash[@attributes.map do |attribute|
              attribute.name
            end.zip(@attributes)]
            @keys = coerce_keys
          end
        end
      RUBY
    end

    context 'on singleton' do

      assert_source <<-RUBY
        def self.foo
          bar
        end
      RUBY

      assert_source <<-RUBY
        def Foo.bar
          bar
        end
      RUBY

    end

    context 'class' do
      assert_source <<-RUBY
        class TestClass

        end
      RUBY

      assert_source <<-RUBY
        class << some_object

        end
      RUBY

      assert_source <<-RUBY
        class << some_object
          the_body
        end
      RUBY

      assert_source <<-RUBY
        class SomeNameSpace::TestClass

        end
      RUBY

      assert_source <<-RUBY
        class Some::Name::Space::TestClass

        end
      RUBY

      assert_source <<-RUBY
        class TestClass < Object

        end
      RUBY

      assert_source <<-RUBY
        class TestClass < SomeNameSpace::Object

        end
      RUBY

      assert_source <<-RUBY
        class TestClass
          def foo
            :bar
          end
        end
      RUBY

      assert_source <<-RUBY
        class ::TestClass

        end
      RUBY
    end

    context 'module' do

      assert_source <<-RUBY 
        module TestModule

        end
      RUBY

      assert_source <<-RUBY
        module SomeNameSpace::TestModule

        end
      RUBY

      assert_source <<-RUBY
        module Some::Name::Space::TestModule

        end
      RUBY

      assert_source <<-RUBY
        module TestModule
          def foo
            :bar
          end
        end
      RUBY

    end

    context 'op assign' do
      %w(|= ||= &= &&= += -= *= /= **= %=).each do |op|
        assert_source "self.foo #{op} bar"
        assert_source "foo[key] #{op} bar"
      end
    end

    context 'element assignment' do
      assert_source 'array[index] = value'
      assert_source 'array[*index] = value'

      %w(+ - * / % & | || &&).each do |operator|
        context "with #{operator}" do
          assert_source "array[index] #{operator}= 2"
          assert_source "array[] #{operator}= 2"
        end
      end
    end

    context 'defined?' do
      assert_source <<-RUBY
        defined?(@foo)
      RUBY

      assert_source <<-RUBY
        defined?(Foo)
      RUBY
    end
  end

  context 'lambda' do
    assert_source <<-RUBY
      lambda do |a, b|
        a
      end
    RUBY
  end

  context 'match operators' do
    assert_source <<-RUBY
      (/bar/ =~ foo)
    RUBY

    assert_source <<-RUBY
      (foo =~ /bar/)
    RUBY
  end

  context 'binary operators methods' do
    %w(+ - * / & | << >> == === != <= < <=> > >= =~ !~ ^ **).each do |operator|
      assert_source "(1 #{operator} 2)"
      assert_source "(left.#{operator}(*foo))"
      assert_source "(left.#{operator}(a, b))"
      assert_source "(self #{operator} b)"
      assert_source "(a #{operator} b)"
      assert_source "(a #{operator} b).foo"
    end
  end

   context 'binary operator' do
     context 'and keywords' do
       assert_source '((a) || (break(foo)))'
     end

     context 'sending methods to result' do
       assert_source '((a) || (b)).foo'
     end

     context 'nested' do
       assert_source '((a) || (((b) || (c))))'
     end
   end

  { :or => :'||', :and => :'&&' }.each do |word, symbol|
    context "word form form equivalency of #{word} and #{symbol}" do
      assert_generates "((a) #{symbol} (break(foo)))", "a #{word} break foo"
    end
  end

  context 'expansion of shortcuts' do
    context 'on += operator' do
      assert_generates 'a = ((a) + (2))', 'a += 2'
    end

    context 'on -= operator' do
      assert_generates 'a = ((a) - (2))', 'a -= 2'
    end

    context 'on **= operator' do
      assert_generates 'a = ((a) ** (2))', 'a **= 2'
    end

    context 'on *= operator' do
      assert_generates 'a = ((a) * (2))', 'a *= 2'
    end

    context 'on /= operator' do
      assert_generates 'a = ((a) / (2))', 'a /= 2'
    end
  end

  context 'shortcuts' do
    context 'on &&= operator' do
      assert_source '(a &&= (b))'
    end

    context 'on ||= operator' do
      assert_source '(a ||= (2))'
    end

    context 'calling methods on shortcuts' do
      assert_source '(a ||= (2)).bar'
    end
  end

 #context 'flip flops' do
 #  context 'flip2' do
 #    assert_source <<-RUBY
 #      if (((i) == (4)))..(((i) == (4)))
 #        foo
 #      end
 #    RUBY
 #  end

 #  context 'flip3' do
 #    assert_source <<-RUBY
 #      if (((i) == (4)))...(((i) == (4)))
 #        foo
 #      end
 #    RUBY
 #  end
 #end

  context 'unary operators' do
    context 'negation' do
      assert_source '!1'
    end

    context 'double negation' do
      assert_source '!!1'
    end

    context 'unary match' do
      assert_source '~a'
    end

    context 'unary minus' do
      assert_source '-a'
    end

    context 'unary plus' do
      assert_source '+a'
    end
  end

  context 'case statement' do
    context 'without else branch' do
      assert_source <<-RUBY
        case 
        when bar
          baz
        when baz
          bar
        end
      RUBY
    end
  end

  context 'receiver case statement' do
    context 'without else branch' do
      assert_source <<-RUBY
        case foo
        when bar
          baz
        when baz
          bar
        end
      RUBY
    end

    context 'with multivalued conditions' do
      assert_source <<-RUBY
        case foo
        when bar, baz
          :other
        end
      RUBY
    end

    context 'with splat operator' do
      assert_source <<-RUBY
        case foo
        when *bar
          :value
        end
      RUBY
    end

    context 'with else branch' do
      assert_source <<-RUBY
        case foo
        when bar
          baz
        else
          :foo
        end
      RUBY
    end
  end

  context 'for' do
    context 'single assignment' do
      assert_source <<-RUBY
        for a in bar do
          baz
        end
      RUBY
    end

    context 'splat assignment' do
      assert_source <<-RUBY
        for a, *b in bar do
          baz
        end
      RUBY
    end

    context 'multiple assignment' do
      assert_source <<-RUBY
        for a, b in bar do
          baz
        end
      RUBY
    end
  end

  context 'loop' do
    assert_source <<-RUBY
      loop do
        foo
      end
    RUBY
  end

  context 'while' do
    context 'single statement in body' do
      assert_source <<-RUBY
        while false
          3
        end
      RUBY
    end

    context 'multiple expressions in body' do
      assert_source <<-RUBY
        while false
          3
          5
        end
      RUBY
    end
  end

  context 'until' do
    context 'with single expression in body' do
      assert_source <<-RUBY
        until false
          3
        end
      RUBY
    end

    context 'with multiple expressions in body' do
      assert_source <<-RUBY 
        while false
          3
          5
        end
      RUBY
    end
  end

  # Note:
  #
  # Do not remove method_call from
  #
  # begin
  #   stuff
  # end.method_call 
  #
  # As 19mode would optimize begin end blocks away
  #
  context 'begin' do
    context 'simple' do
      assert_source <<-RUBY
        begin
          foo
          bar
        end.some_method
      RUBY
    end

    context 'with rescue condition' do
      assert_source <<-RUBY
        x = begin
          foo
        rescue
          bar
        end.some_method
      RUBY
    end

    context 'with with ensure' do
      assert_source <<-RUBY
        begin
          foo
        ensure
          bar
        end.some_method
      RUBY
    end
  end

  context 'rescue' do
    context 'as block' do
      assert_source <<-RUBY
        begin
          foo
          foo
        rescue
          bar
        end
      RUBY
    end
    context 'without rescue condition' do
      assert_source <<-RUBY
        begin
          bar
        rescue
          baz
        end
      RUBY
    end

    context 'within a block' do
      assert_source <<-RUBY
        foo do
          begin
            bar
          rescue
            baz
          end
        end
      RUBY
    end

    context 'with rescue condition' do
      context 'without assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError
            baz
          end
        RUBY
      end

      context 'with assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError => exception
            baz
          end
        RUBY
      end
    end

    context 'with multivalued rescue condition' do
      context 'without assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError, SomeOtherError
            baz
          end
        RUBY
      end

      context 'with assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError, SomeOther => exception
            baz
          end
        RUBY
      end
    end

    context 'with multiple rescue conditions' do
      assert_source <<-RUBY
        begin
          foo
        rescue SomeError
          bar
        rescue
          baz
        end
      RUBY
    end

    context 'with normal and splat condition' do
      context 'without assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError, *bar
            baz
          end
        RUBY
      end

      context 'with assignment' do
        assert_source <<-RUBY
          begin
            bar
          rescue SomeError, *bar => exception
            baz
          end
        RUBY
      end
    end

    context 'with splat condition' do
      context 'without assignment' do
        assert_source <<-RUBY
          defined?(@foo)
        RUBY

        assert_source <<-RUBY
          defined?(Foo)
        RUBY
      end
    end
  end
end
