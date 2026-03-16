#!/bin/bash
cp /etc/rancher/k3s/k3s.yaml /home/scrapps/.kube/config
chown scrapps:scrapps /home/scrapps/.kube/config
chmod 666 /home/scrapps/.kube/config
sudo -u scrapps bash -c "/usr/local/bin/kubectl --kubeconfig /home/scrapps/.kube/config get nodes"
sudo -u scrapps bash -c "/home/scrapps/.local/bin/k9s --kubeconfig /home/scrapps/.kube/config"