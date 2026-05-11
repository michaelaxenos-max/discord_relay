require "net/http"
require "uri"
require "json"
require "base64"

class SheetsWriter
  SPREADSHEET_ID = "1Mczh0xJgnXxN3n36hx6hzxxLBjtIM83YD3tXzEJ4hno".freeze
  SHEET_NAME     = "Testing".freeze
  HEADER_ROW     = 2

  def self.write_by_header(row_number, header_name, value)
    new.write_by_header(row_number, header_name, value)
  end

  def write_by_header(row_number, header_name, value)
    col = find_column(header_name)
    raise "Column '#{header_name}' not found in sheet headers" unless col

    write_cell("#{SHEET_NAME}!#{col}#{row_number}", value)
  end

  private

  def find_column(header_name)
    encoded = URI.encode_www_form_component("#{SHEET_NAME}!#{HEADER_ROW}:#{HEADER_ROW}")
    uri = URI("https://sheets.googleapis.com/v4/spreadsheets/#{SPREADSHEET_ID}/values/#{encoded}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{access_token}"

    headers = JSON.parse(http.request(req).body).dig("values", 0) || []
    idx = headers.index(header_name)
    idx ? col_letter(idx + 1) : nil
  end

  def write_cell(range, value)
    encoded = URI.encode_www_form_component(range)
    uri = URI("https://sheets.googleapis.com/v4/spreadsheets/#{SPREADSHEET_ID}/values/#{encoded}?valueInputOption=RAW")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Put.new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    req["Content-Type"]  = "application/json"
    req.body = { range: range, majorDimension: "ROWS", values: [ [ value.to_s ] ] }.to_json

    res = http.request(req)
    raise "Sheets write failed #{res.code}: #{res.body}" unless res.code == "200"
  end

  def col_letter(n)
    result = ""
    while n > 0
      n, rem = (n - 1).divmod(26)
      result.prepend((65 + rem).chr)
    end
    result
  end

  def access_token
    key_data = JSON.parse(Base64.decode64(ENV.fetch("GOOGLE_SERVICE_ACCOUNT_JSON")))
    now = Time.now.to_i
    payload = {
      iss:   key_data["client_email"],
      scope: "https://www.googleapis.com/auth/spreadsheets",
      aud:   "https://oauth2.googleapis.com/token",
      iat:   now,
      exp:   now + 3600
    }
    private_key = OpenSSL::PKey::RSA.new(key_data["private_key"])
    jwt = JWT.encode(payload, private_key, "RS256")

    uri = URI("https://oauth2.googleapis.com/token")
    res = Net::HTTP.post_form(uri, "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion" => jwt)
    JSON.parse(res.body).fetch("access_token")
  end
end
