Plugin.define "choice" do

  author "Syn"
  name "Choice"
  version "1.0"

  assign :yes_no,  ["Yes", "No"]
  assign :words,   ["are", "does", "is", "should", "will"]

  words.each do |word|
    word = word.to_sym()

    command word do |event|
      msg = do_choice(event)
      event.reply(msg)
    end

    help_for word do 
      "{cmd}[#{words.join("|")}] <subject> <question>? " +
      "-- Ask a question. Multiple choice questions are separated by commas " + 
      "or \" or \".\n" +
      "Example: {cmd}should I eat cake or go jogging? ...or... " + 
      "{cmd}will I get lucky?"
    end
  end

  on :start do
    assign :sayings, config.get("saying", yes_no)
  end

  helper :do_choice do |event|
    text = event.message.strip()

    if text.any?
      options = self.parse_options(text)
      case options.length
      when 1
        msg = sayings[rand(sayings.length())]
      else
        msg = options[rand(options.length())]
      end
    else
      msg = "Maybe you should ask a question?"
    end

    msg
  end

  helper :parse_options do |txt|
    options = []
    sre = /\,?\s+or\s+|\,\s+/

    # Get rid of the question mark if there is one 
    # and the subject.
    txt.strip!
    txt.sub!(/\?$/, "")
    txt.sub!(/^\w+\s+/, "")

    options = txt.split(sre)
    options.collect! {|s| s.strip }
    
    options
  end

end
