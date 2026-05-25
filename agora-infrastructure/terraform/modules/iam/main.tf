locals {
  oidc_provider = replace(var.eks_oidc_issuer_url, "https://", "")
}

# MSK IAM IRSA Roles
# Each service gets its own IAM role with least-privilege Kafka permissions

resource "aws_iam_role" "traffic_optimizer_msk" {
  name = "agora-${var.environment}-traffic-optimizer-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["traffic-optimizer"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-traffic-optimizer-msk"
  })
}

resource "aws_iam_role" "anomaly_detector_msk" {
  name = "agora-${var.environment}-anomaly-detector-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["anomaly-detector"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-anomaly-detector-msk"
  })
}

resource "aws_iam_role" "energy_optimizer_msk" {
  name = "agora-${var.environment}-energy-optimizer-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["energy-optimizer"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-energy-optimizer-msk"
  })
}

resource "aws_iam_role" "data_broker_msk" {
  name = "agora-${var.environment}-data-broker-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["data-broker"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-data-broker-msk"
  })
}

resource "aws_iam_role" "kafka_connect_msk" {
  name = "agora-${var.environment}-kafka-connect-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["kafka-connect"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-kafka-connect-msk"
  })
}

resource "aws_iam_role" "schema_registry_msk" {
  name = "agora-${var.environment}-schema-registry-msk"

  assume_role_policy = data.aws_iam_policy_document.irsa_trust["schema-registry"].json

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-schema-registry-msk"
  })
}

# IRSA trust policies
data "aws_iam_policy_document" "irsa_trust" {
  for_each = toset(["traffic-optimizer", "anomaly-detector", "energy-optimizer", "data-broker", "kafka-connect", "schema-registry"])

  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:city-services:${each.key}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# MSK IAM access policies
data "aws_iam_policy_document" "traffic_optimizer_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/vehicle.telemetry",
      "${var.msk_cluster_arn}/topic/signal.events",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Write",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/signal.commands",
      "${var.msk_cluster_arn}/topic/incidents",
    ]
  }
}

data "aws_iam_policy_document" "anomaly_detector_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/vehicle.telemetry",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Write",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/incidents",
      "${var.msk_cluster_arn}/topic/alerts.notifications",
    ]
  }
}

data "aws_iam_policy_document" "energy_optimizer_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/sensor.environmental",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Write",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/alerts.notifications",
    ]
  }
}

data "aws_iam_policy_document" "data_broker_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/vehicle.telemetry",
      "${var.msk_cluster_arn}/topic/sensor.environmental",
      "${var.msk_cluster_arn}/topic/signal.events",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Write",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/data.anonymized.vehicle",
      "${var.msk_cluster_arn}/topic/data.inventor.traffic",
    ]
  }
}

data "aws_iam_policy_document" "kafka_connect_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_data_lake_bucket_arn,
      "${var.s3_data_lake_bucket_arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "schema_registry_msk" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup",
    ]
    resources = [
      var.msk_cluster_arn,
      "${var.msk_cluster_arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Read",
      "kafka-cluster:Write",
      "kafka-cluster:Describe",
    ]
    resources = [
      "${var.msk_cluster_arn}/topic/_schemas",
    ]
  }
}

# Attach MSK policies to IRSA roles
resource "aws_iam_role_policy" "traffic_optimizer_msk" {
  name   = "agora-${var.environment}-traffic-optimizer-msk"
  role   = aws_iam_role.traffic_optimizer_msk.id
  policy = data.aws_iam_policy_document.traffic_optimizer_msk.json
}

resource "aws_iam_role_policy" "anomaly_detector_msk" {
  name   = "agora-${var.environment}-anomaly-detector-msk"
  role   = aws_iam_role.anomaly_detector_msk.id
  policy = data.aws_iam_policy_document.anomaly_detector_msk.json
}

resource "aws_iam_role_policy" "energy_optimizer_msk" {
  name   = "agora-${var.environment}-energy-optimizer-msk"
  role   = aws_iam_role.energy_optimizer_msk.id
  policy = data.aws_iam_policy_document.energy_optimizer_msk.json
}

resource "aws_iam_role_policy" "data_broker_msk" {
  name   = "agora-${var.environment}-data-broker-msk"
  role   = aws_iam_role.data_broker_msk.id
  policy = data.aws_iam_policy_document.data_broker_msk.json
}

resource "aws_iam_role_policy" "kafka_connect_msk" {
  name   = "agora-${var.environment}-kafka-connect-msk"
  role   = aws_iam_role.kafka_connect_msk.id
  policy = data.aws_iam_policy_document.kafka_connect_msk.json
}

resource "aws_iam_role_policy" "schema_registry_msk" {
  name   = "agora-${var.environment}-schema-registry-msk"
  role   = aws_iam_role.schema_registry_msk.id
  policy = data.aws_iam_policy_document.schema_registry_msk.json
}

data "aws_caller_identity" "current" {}

# Cross-account S3 data lake access
data "aws_iam_policy_document" "s3_data_lake_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_data_lake_bucket_arn,
      "${var.s3_data_lake_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "s3_data_lake_access" {
  name        = "agora-${var.environment}-data-lake-access"
  description = "Cross-account access policy for Agora data lake"
  policy      = data.aws_iam_policy_document.s3_data_lake_access.json

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-data-lake-access"
  })
}

resource "aws_iam_role" "s3_data_lake_cross_account" {
  count = var.data_lake_consumer_account_id != null ? 1 : 0
  name  = "agora-${var.environment}-data-lake-xacct"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.data_lake_consumer_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "agora-${var.environment}-data-lake"
        }
      }
    }]
  })

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-data-lake-xacct"
  })
}

resource "aws_iam_role_policy_attachment" "s3_data_lake_access" {
  count      = var.data_lake_consumer_account_id != null ? 1 : 0
  role       = aws_iam_role.s3_data_lake_cross_account[0].name
  policy_arn = aws_iam_policy.s3_data_lake_access.arn
}
