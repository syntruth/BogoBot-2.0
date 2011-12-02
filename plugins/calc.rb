Plugin.define "calc" do

  # Allows numbers, hex in the form of 0xFF and parens.
  assign :allowed, "0123456789abcedfx+-/*().%<>&|".split(//)

  name    "Calc"
  author  "Randy"
  version "1.0b"

  helper :do_calc do |event|
    text = event.message
    parts = text.downcase.gsub(/\s+/, "").split(//)
    bad = parts - (parts & allowed)

    if bad.any?
      msg = "#{event.from}: There are unallowed characters. " + 
        "Bad characters: #{bad.join("")}"
    else
      begin
        msg = "#{event.from}, the answer is: " + eval(text).to_s()
      rescue Exception => err
        msg = "Error in calculation: #{err}"
      end
    end

    msg
  end

  command :calc do |event|
    msg = do_calc(event)
    event.reply(msg)
  end

  help_for :calc do
    "{cmd}calc <string> -- Calulates string. " +
    "Allowed characters: #{allowed.join("")}"
  end

end
