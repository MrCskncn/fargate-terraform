# AWS Fargate Terraform Demo

## Gerekli Şeyler :)

1- Terraform v0.13+ ve bir Code Editor

2- AWS hesabı ve US East 1 (N. Virginia)'da default bir VPC.

3- AWS IAM'den, AdministratorAccess'i olan bir Programmatic Access kullanıcısı yaratıp, ilgili credential'ları main.tf dosyasında en tepedeki Access Key ve Secret Key kısımlarına yazıyoruz.

4- Artık aşağıdaki komutları çalıştırmaya hazırız:

--
```
$ terraform init
$ terraform plan
$ terraform apply
```

5- Bir de şöyle bir repomuz var https://github.com/MrCskncn/fargate-app.git, bu repo'da da örnek bir Java uygulaması bulunuyor. Buradan buildspec.yaml gibi bazı dosyalarda değişiklikler yapıyor olacağız, o yüzden iki repoyu da git clone yapalım. (Sunum anına kadar güncellenebilirler, dikkat!)

Sunumda görüşürüz!


## İşimiz bitince de aşağıdaki komut ile her şeyi silmeyi unutmayalım!

```
$ terraform destroy
```