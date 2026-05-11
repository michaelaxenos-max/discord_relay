require "net/http"
require "uri"
require "json"
require "base64"

class SheetsReader
  SPREADSHEET_ID = SheetsWriter::SPREADSHEET_ID
  SHEET_NAME     = SheetsWriter::SHEET_NAME
  HEADER_ROW     = SheetsWriter::HEADER_ROW

  # Returns array of { row_number: N, data: { "Column Header" => "value" } }
  # Rows with all-blank values are skipped.
  def all_rows
    raw    = fetch_range("#{SHEET_NAME}!#{HEADER_ROW}:3000")
    values = raw["values"] || []
    return [] if values.size < 2

    headers   = values.first
    data_rows = values[1..]

    data_rows.each_with_index.filter_map do |row, idx|
      next if row.all?(&:blank?)

      row_number = HEADER_ROW + 1 + idx
      data = headers.each_with_index.with_object({}) do |(header, col_idx), hash|
        hash[header] = row[col_idx].to_s.strip
      end
      { row_number: row_number, data: data }
    end
  end

  private

  def fetch_range(range)
    encoded = URI.encode_www_form_component(range)
    uri     = URI("https://sheets.googleapis.com/v4/spreadsheets/#{SPREADSHEET_ID}/values/#{encoded}")
    http    = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    res = http.request(req)
    raise "Sheets read failed #{res.code}: #{res.body}" unless res.code == "200"
    JSON.parse(res.body)
  end

  def access_token
    key_data    = JSON.parse(Base64.decode64(ENV.fetch("GOOGLE_SERVICE_ACCOUNT_JSON")))
    now         = Time.now.to_i
    payload     = {
      iss:   key_data["client_email"],
      scope: "https://www.googleapis.com/auth/spreadsheets",
      aud:   "https://oauth2.googleapis.com/token",
      iat:   now,
      exp:   now + 3600
    }
    private_key = OpenSSL::PKey::RSA.new(key_data["private_key"])
    jwt         = JWT.encode(payload, private_key, "RS256")

    uri = URI("https://oauth2.googleapis.com/token")
    res = Net::HTTP.post_form(uri, "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion" => jwt)
    JSON.parse(res.body).fetch("access_token")
  end
end
