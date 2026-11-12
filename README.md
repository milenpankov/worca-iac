# worca-iac

Infrastructure as code for running [Worca](https://github.com/SinishaDjukic/worca-cc) with its
controller/worker topology (a controller, plus a container or pod per run and chat thread) and
sign-in through your own identity provider.

| Platform | Folder |
|---|---|
| AWS EKS | [aws-eks/](aws-eks) |

Each platform is self-contained: its own Terraform roots, values and README. Nothing is shared
between platforms until a second one shows what is really common.

## License

[MIT](LICENSE)
