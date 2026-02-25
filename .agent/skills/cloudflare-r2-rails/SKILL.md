---
description: How to integrate Cloudflare R2 (S3-compatible) object storage in a Rails app
---

# Cloudflare R2 Integration with Rails

Use this pattern when you need cloud file storage in a Rails app using Cloudflare R2
(S3-compatible, zero egress fees). Uses the `aws-sdk-s3` gem — no R2-specific SDK needed.

## 1. Add the gem

```ruby
# Gemfile
gem "aws-sdk-s3", "~> 1.0", require: false  # lazy-loaded to reduce boot time
```

## 2. Environment variables

```bash
CLOUDFLARE_R2_ACCESS_KEY_ID=your_access_key
CLOUDFLARE_R2_SECRET_ACCESS_KEY=your_secret_key
CLOUDFLARE_R2_BUCKET=your-bucket-name
CLOUDFLARE_R2_ENDPOINT=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

**How to get these:**
1. Cloudflare Dashboard → R2 Object Storage → Create bucket
2. R2 → Manage R2 API Tokens → Create API Token
3. Account ID is in your dashboard URL or sidebar

## 3. R2-specific S3 client configuration

```ruby
require "aws-sdk-s3"

client = Aws::S3::Client.new(
  access_key_id: ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"],
  secret_access_key: ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"],
  endpoint: ENV["CLOUDFLARE_R2_ENDPOINT"],
  region: "auto",            # R2 requires "auto", not a real AWS region
  force_path_style: true     # R2 requires path-style (not virtual-hosted)
)
```

**Key gotchas:**
- `region: "auto"` — R2 does not use AWS regions. Must be exactly `"auto"`.
- `force_path_style: true` — R2 requires path-style URLs, not virtual-hosted-style.
- `endpoint` format — `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` (no bucket in URL).

## 4. Upload and download

```ruby
# Upload
client.put_object(
  bucket: "your-bucket",
  key: "path/to/file.png",
  body: file_data,           # binary string or IO
  content_type: "image/png"
)

# Download
response = client.get_object(bucket: "your-bucket", key: "path/to/file.png")
data = response.body.read
```

## 5. Service pattern with local fallback

For development without R2 credentials, fall back to local `tmp/` storage:

```ruby
class FileUploader
  def initialize
    @configured = ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"].present? &&
                  ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"].present? &&
                  ENV["CLOUDFLARE_R2_ENDPOINT"].present?
  end

  def upload(data, key)
    return upload_local(data, key) unless @configured
    client.put_object(bucket: bucket, key: key, body: data)
    key
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("R2 upload failed: #{e.message}")
    upload_local(data, key)
  end

  def download(key_or_path)
    if key_or_path.start_with?("/local/")
      File.binread(Rails.root.join("tmp", key_or_path.sub(%r{^/}, "")))
    elsif @configured
      client.get_object(bucket: bucket, key: key_or_path).body.read
    else
      raise "Cannot download: R2 not configured"
    end
  end

  private

  def client
    @client ||= begin
      require "aws-sdk-s3"
      Aws::S3::Client.new(
        access_key_id: ENV["CLOUDFLARE_R2_ACCESS_KEY_ID"],
        secret_access_key: ENV["CLOUDFLARE_R2_SECRET_ACCESS_KEY"],
        endpoint: ENV["CLOUDFLARE_R2_ENDPOINT"],
        region: "auto",
        force_path_style: true
      )
    end
  end

  def bucket
    ENV.fetch("CLOUDFLARE_R2_BUCKET", "my-bucket")
  end

  def upload_local(data, key)
    path = Rails.root.join("tmp", "local", key)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, data)
    "/local/#{key}"
  end
end
```

## 6. Public access options

| Option | When to use |
|--------|-------------|
| **No public access** | Server-side only (AI processing, email attachments). Store R2 key, download via S3 API. |
| **R2.dev subdomain** | Quick public URLs without custom domain. Enable in bucket settings. Rate-limited. |
| **Custom domain** | Production public access. Requires domain on Cloudflare. No rate limits. |

For server-side-only access (like email inline attachments), you do NOT need public access.
Store the object key in your database and download via the S3 API when needed.

## 7. Cost

- Storage: $0.015/GB/month (10GB free)
- Uploads (Class A): $4.50/million (1M free/month)
- Downloads (Class B): $0.36/million (10M free/month)
- **Egress: $0 always** (this is R2's killer feature vs S3)

For a small app doing <1000 uploads/month, R2 is effectively free.
